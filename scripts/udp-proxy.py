#!/usr/bin/env python3
"""Multi-client UDP proxy: 0.0.0.0:PORT  ->  TARGET_IP:PORT.

Replaces socat (whose 'UDP-LISTEN,fork' mangles demultiplexing with more than one concurrent
client). Keeps a separate upstream socket per client, so replies from the VM go back to the right
player. No dependencies (pure stdlib). One process per port.

Usage: udp-proxy.py <listen_port> <target_ip> [target_port=listen_port] [idle_sec=180]
"""
import socket, select, sys, time

def main():
    if len(sys.argv) < 3:
        print("usage: udp-proxy.py <listen_port> <target_ip> [target_port] [idle_sec]", file=sys.stderr)
        sys.exit(2)
    lport = int(sys.argv[1])
    tip = sys.argv[2]
    tport = int(sys.argv[3]) if len(sys.argv) > 3 else lport
    idle = float(sys.argv[4]) if len(sys.argv) > 4 else 180.0

    lsock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
    lsock.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
    lsock.bind(("0.0.0.0", lport))

    clients = {}      # client_addr -> [upstream_sock, last_seen]
    up_to_client = {} # upstream_sock -> client_addr

    while True:
        socks = [lsock] + list(up_to_client.keys())
        r, _, _ = select.select(socks, [], [], 30.0)
        now = time.monotonic()
        for s in r:
            if s is lsock:
                data, caddr = lsock.recvfrom(65535)
                ent = clients.get(caddr)
                if ent is None:
                    up = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
                    up.connect((tip, tport))
                    ent = [up, now]
                    clients[caddr] = ent
                    up_to_client[up] = caddr
                else:
                    ent[1] = now
                try:
                    ent[0].send(data)
                except OSError:
                    pass
            else:
                caddr = up_to_client.get(s)
                try:
                    data, _ = s.recvfrom(65535)
                except OSError:
                    continue
                if caddr is not None:
                    lsock.sendto(data, caddr)
                    ent = clients.get(caddr)
                    if ent: ent[1] = now
        # reap idle clients
        for caddr, ent in list(clients.items()):
            if now - ent[1] > idle:
                up = ent[0]
                up_to_client.pop(up, None)
                clients.pop(caddr, None)
                try: up.close()
                except OSError: pass

if __name__ == "__main__":
    main()
