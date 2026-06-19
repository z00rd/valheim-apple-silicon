# Roadmapa — naprawa laga zdalnego gracza

> Status na 2026-06-19. Serwer **działa**; jedyny otwarty problem to rubber-banding u
> ZDALNEGO gracza (Jasiek). Host i gracze w tej samej sieci grają płynnie.
> Kontekst i diagnoza: `TROUBLESHOOTING.md` #14 oraz `SETUP-LOG.md` (dziennik 2026-06-18→19).

---

## Model myślowy: to DWA niezależne problemy, nie jeden

| Oś | Co to | Czy boli zdalnego gracza? |
|---|---|---|
| **Emulacja (CPU)** | serwer x86 na M1 → QEMU, podatek ~1,2 rdzenia na idle | **NIE** — CPU ma zapas; gdyby nie nadążał, ścinałoby WSZYSTKICH równo, a host gra OK |
| **Sieć (NAT)** | sidecar Tailscale siedzi **wewnątrz VM** → symetryczny NAT slirp QEMU → relay DERP | **TAK** — to JEDYNA realna przyczyna laga Jaśka |

**Wniosek:** lag Jaśka to wyłącznie **oś sieci**. Emulacja jest kosmetyczna (działa, tylko
grzeje). Każdy fix oceniamy po jednym kryterium: czy daje **easy NAT → direct P2P**.

Dlaczego symetryczny NAT: węzeł Tailscale (`valheim-server`, `100.119.242.14`) to kontener
w `docker-compose.yml` z `network_mode: service:tailscale`, uruchamiany **w maszynie Colima/QEMU**.
Widzi sieć przez slirp QEMU → `MappingVariesByDestIP=true`. **Sam Mac NIE jest za symetrycznym
NAT-em** — siedzi za routerem ASUS (easy NAT, NAT-PMP). To kluczowa obserwacja dla Opcji 1.

---

## Mapa możliwości

| # | Opcja | Emulacja | NAT → direct? | Wysiłek | Koszt | Host-independent | Ryzyko |
|---|---|---|---|---|---|---|---|
| 0 | Status quo (TS w VM) | tak | ❌ DERP | — | 0 | ✅ | działa, ale Jasiek laguje |
| 1 | **TS na hoście Maca** | tak | ✅ Mac za easy NAT | **najmniejszy** | 0 | ✅ | tylko: czy Colima forwarduje UDP |
| 2 | Wired + Colima bridged | tak | ✅ true direct | duży | adapter ~50 zł | ✅ | recreate VM (świat do zipa) |
| 3 | Peer Relay (invite-as-user) | tak | ⚠️ relay, nie direct | średni | 0 | ❌ relay musi być online | — |
| 4 | x86 mini PC + kabel | **nie (natywnie)** | ✅ za ASUS | duży | 0 | ✅ | patrz „Mini PC" niżej |
| 5 | Płatny host | nie | ✅ public IP | mały | $/mc | ✅ | brak (poza kosztem) |

---

## GATE — najpierw `netcheck` Jaśka (poniedziałek)

Wszystko zależy od NAT-u Jaśka. Direct P2P wymaga easy NAT po **obu** stronach.

- Jasiek `MappingVariesByDestIP=false` (easy) → **idź w Opcję 1** (i ewentualnie 2).
- Jasiek `true` / CGNAT (twardy NAT) → direct praktycznie niemożliwy niezależnie od naszej
  strony → przeskocz do **Opcji 3** (Peer Relay) lub docelowo **5** (płatny host).

Instrukcja dla Jaśka na końcu tego pliku.

> Rada: **nie kupuj adaptera Ethernet** (Opcja 2), dopóki netcheck Jaśka nie pokaże `false`.

---

## Opcja 1 — Tailscale na hoście Maca (REKOMENDOWANA, zacznij tu)

Idea: przenieś węzeł Tailscale z VM na **sam macOS**. Wtedy węzłem tailnetu jest Mac (za easy
NAT ASUS-a), a do kontenera w VM idzie tylko lokalny forward UDP. Mac easy NAT → direct do Jaśka,
**bez kabla, bez relayu, 0 zł**.

### Kroki

1. **Backup świata** (zawsze przed zmianami):
   ```bash
   ./scripts/play.sh        # podnieś, jeśli stoi
   ./scripts/backup.sh
   ```
2. **Zainstaluj Tailscale na macOS** (nie w kontenerze!) — app z Mac App Store / strony Tailscale
   albo CLI:
   ```bash
   brew install tailscale
   sudo brew services start tailscale     # uruchamia tailscaled na hoście
   tailscale up                            # zaloguj, węzeł = ten Mac
   ```
3. **Zdejmij sidecar TS z compose**, opublikuj porty z kontenera valheim. W `docker-compose.yml`:
   - usuń serwis `tailscale` oraz z serwisu `valheim` linię `network_mode: service:tailscale`
     i `depends_on: [tailscale]`,
   - dodaj do `valheim`:
     ```yaml
     ports:
       - "2456:2456/udp"
       - "2457:2457/udp"
     ```
   (Colima forwarduje publikowane porty kontenera na host Maca.)
4. **Restart stacku:**
   ```bash
   docker --context colima-valheim compose up -d
   ```
5. **Weryfikacja (na Macu):**
   ```bash
   tailscale netcheck        # CEL: MappingVariesByDestIP: false  + PortMapping niepuste
   tailscale ip -4           # nowy adres serwera = adres TEGO Maca w tailnecie
   tailscale ping <ip-jaśka> # CEL: "direct", nie "via DERP"
   ```
6. **Zaktualizuj „Join IP" u graczy** — adres zmienia się z `100.119.242.14` (stary węzeł VM)
   na adres Maca. Udostępnij węzeł Maca znajomym (Share) i w panelu **Disable key expiry**.

### Ryzyko / rzecz do sprawdzenia
- **Forward UDP przez Colima/Lima** bywa zawodny (historycznie nastawiony na TCP). Jeśli po
  starcie gra nie łapie połączenia: fallback — Colima z własnym IP VM
  (`--network-address`, vmnet) i `tailscale serve`/forward na hoście do `IP_VM:2456`, albo
  od razu Opcja 2 (bridged). To jedyne realne ryzyko tej ścieżki — reszta jest trywialna.

---

## Opcja 2 — Wired Ethernet + Colima bridged (true direct, gdy 1 nie wystarczy)

Najniższy możliwy ping (most L2, VM dostaje realne IP za samym ASUS-em). Wymaga **kabla** —
most L2 nie działa po WiFi (Mac bez portu → adapter USB-C→GbE).

1. Backup świata do zipa (`backup.sh`), bo będzie `colima delete`.
2. socket_vmnet + uprawnienia (`limactl sudoers`, sudo).
3. `colima delete valheim` → recreate z `--network-address --network-interface <eth>`
   (interfejs = adapter Ethernet, NIE en0/WiFi).
4. Add-ony sieciowe: sidecar TS `network_mode: host` + `--port=41641`.
5. Weryfikacja: `tailscale netcheck` → `MappingVariesByDestIP: false`; `tailscale ping` → direct.
6. Opcjonalnie NAT-PMP na ASUS-ie.

---

## Opcja 3 — Peer Relay (fallback bez kabla, gdy Jasiek ma twardy NAT)

Uwaga: **samo zaproszenie-jako-user NIE naprawia laga** — tylko ODBLOKOWUJE Peer Relay
(Share go blokuje). To wciąż **relay** (wyższy ping niż direct), ale prywatny/UDP, dużo lepszy
niż publiczny DERP. Relay-node musi być online → gorzej z host-independence.

1. Zaproś Jaśka jako **usera** tailnetu (NIE Share; najlepiej zawęź ACL, by nie wystawiać mu
   całej sieci).
2. Postaw Peer Relay na dobrze podłączonym węźle **w tej samej sieci co serwer** (np. stacjonarka
   `megalodon` na `starless`) — wtedy hop serwer↔relay jest lokalny, omija NAT QEMU.
3. Świeży klient Tailscale na wszystkich węzłach (Peer Relay to nowa funkcja).
4. Weryfikacja: `tailscale ping` → przez peer-relay, nie DERP.

---

## Opcja 4 — osobny x86 mini PC (NIE box od Home Assistant)

Rozbija OBA problemy: natywny x86 (zero emulacji) + kabel do ASUS (easy NAT) + 24/7 (host-indep).
Najpełniejsze rozwiązanie — **ale tylko na DEDYKOWANYM boxie**.

### Dlaczego NIE na mini PC od HeatFlow (HA)
Sprawdzone w projekcie `heatflow`: **Intel N100, 16GB, HAOS**, na **WiFi do `starless_ha`**
(wolny IoT AP). Odradzam dokładanie tam Valheima:
1. **System krytyczny** — steruje piecem gazowym (bezwładność 4-8h) + zbiera dane do modelu ML.
   Głodny CPU serwer gry = lagi automatyzacji/gorsze dane; crash Valheima nie może ruszać grzania.
2. **N100 słaby i współdzielony** — Valheim sam jest graniczny na N100; z HA+InfluxDB+Grafana
   ryzykujesz oba naraz.
3. **HAOS to appliance** — dowolne kontenery są niewspierane (Portainer/SSH bez protekcji),
   kruche przy aktualizacjach HAOS.
4. Box i tak jest na **wolnym `starless_ha`** — trzeba by go przepiąć kablem na ASUS.

Werdykt: jako współlokator HA — **nie**. Jako osobny węzeł — najlepszy z listy.

---

## Opcja 5 — płatny host (ostateczność przed Deep North)

Publiczny IP eliminuje cały problem NAT. Świat w zipie gotowy do migracji. Koszt miesięczny.

---

## Cel i deadline
- **Host-independence:** każdy ma móc wbić sam, serwer niezależny od tego kto online.
- **Deadline:** dodatek „Deep North" (~sierpień 2026). Jak do wtedy zdalny lag nierozwiązany → Opcja 5.

## Kolejność działań
1. **Poniedziałek:** Jasiek robi `netcheck` (instrukcja niżej) → znamy jego NAT.
2. Jasiek `false` → **Opcja 1** (0 zł, nic nie psuje). Nie wyszło UDP-forward → Opcja 2.
3. Jasiek `true`/CGNAT → **Opcja 3** (Peer Relay), docelowo **5**.
4. Osobny x86 mini PC pojawi się kiedyś → **Opcja 4**. Boxa HA nie ruszamy.

---

## 📋 INSTRUKCJA DLA JAŚKA — co zrobić w poniedziałek (dla laika)

Cześć! Diagnozujemy, czemu u Ciebie (i tylko u Ciebie) gra się ślizga. Potrzebuję jednej
informacji z Twojego kompa. Zajmie 2 minuty. Robisz to **na komputerze, na którym grasz**.

### Windows
1. Sprawdź, że **Tailscale jest włączony** — ikonka przy zegarku (prawy dolny róg) ma być
   aktywna/zalogowana. Jak nie — kliknij i się zaloguj.
2. Naciśnij klawisz **Windows**, wpisz `cmd`, naciśnij **Enter** (otworzy się czarne okno).
3. Wklej dokładnie tę linijkę i naciśnij **Enter**:
   ```
   tailscale netcheck
   ```
   - Gdyby wyskoczyło „nie jest rozpoznawane jako polecenie", wklej zamiast tego:
     ```
     "C:\Program Files\Tailscale\tailscale.exe" netcheck
     ```
4. Pojawi się kilkanaście linijek. **Zrób zrzut ekranu CAŁOŚCI** (klawisz `PrtScn` albo
   `Win+Shift+S`) i wyślij mi. Najważniejsza jest linijka:
   ```
   - MappingVariesByDestIP: true   (albo false)
   ```
5. **Bonus** (jak Ci się chce) — wklej jeszcze to i wyślij wynik (ma napisać `direct` albo `via DERP`):
   ```
   tailscale ping 100.119.242.14
   ```

### Mac (gdybyś grał na Macu)
Otwórz **Terminal** (Cmd+Spacja → wpisz `Terminal` → Enter) i wklej:
```
tailscale netcheck
```
Jak powie „command not found", to spróbuj: `/Applications/Tailscale.app/Contents/MacOS/Tailscale netcheck`.
Wyślij mi zrzut całości (najważniejsza linijka `MappingVariesByDestIP`).

### Co dalej
- Wyjdzie **`false`** → mam łatwą poprawkę po swojej stronie, gramy bez laga, bez kupowania
  niczego.
- Wyjdzie **`true`** → trudniejszy przypadek, ale mam plan B (prywatny relay). Też ogarniemy.

Dzięki! 🪓
