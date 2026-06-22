#!/usr/bin/env python3
"""Multi-client UDP proxy: 0.0.0.0:PORT  ->  TARGET_IP:PORT.

Replaces socat (whose 'UDP-LISTEN,fork' mangles demultiplexing with more than one concurrent
client). Keeps a separate upstream socket per client, so replies from the VM go back to the right
player. No dependencies (pure stdlib). One process per port.

Robustness: a transient send error never takes the whole proxy down (it would drop every player on
the port); a dead upstream socket (e.g. the container restarted) is dropped so the client can
re-establish. Idle client mappings are reaped after `idle_sec` so the table doesn't grow forever.

Usage: udp-proxy.py <listen_port> <target_ip> [target_port=listen_port] [idle_sec=180]
"""
import socket, select, sys, time

REAP_EVERY = 30.0  # how often to scan for idle clients (not per-packet)

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

    clients = {}       # client_addr -> [upstream_sock, last_seen]
    up_to_ent = {}     # upstream_sock -> (client_addr, entry)   single reverse map (no double lookup)
    socks = [lsock]
    dirty = False      # rebuild `socks` only when client set changes (not every packet)
    next_reap = time.monotonic() + REAP_EVERY

    def drop(up):
        info = up_to_ent.pop(up, None)
        if info:
            clients.pop(info[0], None)
        try: up.close()
        except OSError: pass

    while True:
        if dirty:
            socks = [lsock] + list(up_to_ent.keys()); dirty = False
        r, _, _ = select.select(socks, [], [], REAP_EVERY)
        now = time.monotonic()
        for s in r:
            if s is lsock:
                try:
                    data, caddr = lsock.recvfrom(65535)
                except OSError:
                    continue
                ent = clients.get(caddr)
                if ent is None:
                    up = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
                    try:
                        up.connect((tip, tport))
                    except OSError:
                        up.close(); continue
                    ent = [up, now]
                    clients[caddr] = ent
                    up_to_ent[up] = (caddr, ent)
                    dirty = True
                else:
                    ent[1] = now
                try:
                    ent[0].send(data)
                except OSError:
                    pass
            else:
                info = up_to_ent.get(s)
                try:
                    data, _ = s.recvfrom(65535)
                except OSError:
                    # upstream is dead (e.g. container restarted) → drop the mapping so the
                    # client re-establishes on its next packet instead of looping on a dead socket
                    drop(s); dirty = True
                    continue
                if info is not None:
                    caddr, ent = info
                    try:
                        lsock.sendto(data, caddr)
                    except OSError:
                        pass
                    ent[1] = now
        # reap idle clients — throttled, NOT on every packet
        if now >= next_reap:
            next_reap = now + REAP_EVERY
            for caddr, ent in list(clients.items()):
                if now - ent[1] > idle:
                    drop(ent[0]); dirty = True

if __name__ == "__main__":
    main()
