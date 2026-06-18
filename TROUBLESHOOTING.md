# Troubleshooting — pułapki i rozwiązania

Realne problemy napotkane przy stawianiu tego serwera na Macu M1 (Apple Silicon) i jak je
rozwiązać. Skróty komend zakładają, że jesteś w katalogu projektu.

> Kontekst dockera w skryptach: `export DOCKER_CONTEXT=colima-valheim` (robią to za Ciebie).
> Logi serwera na żywo: `./scripts/logs.sh` · pełny stan: `./scripts/status.sh`

---

### 1. VM nie wstaje: `guest agent binary could not be found for Linux-x86_64`
Lima (pod Colimą) ma agenta gościa tylko dla architektury natywnej (arm64); dla VM **x86_64**
potrzebny jest osobny pakiet.
```bash
brew install lima-additional-guestagents
colima delete valheim --force      # sprzątnij nieudaną próbę (obraz zostaje w cache)
./scripts/setup.sh
```

### 2. `colima start --vm-type qemu` pada: brak qemu
Colima do emulacji x86_64 potrzebuje binarki QEMU (nie zawsze dociągana z `colima`).
```bash
brew install qemu
```

### 3. Docker Desktop + Rosetta zamiast tego? — NIE
Obraz serwera (mono/Unity) **crashuje** pod „Use Rosetta for x86/amd64 emulation" w Docker
Desktop (błąd codegen mono / SIGABRT). Dlatego ten projekt używa **Colima + pełny QEMU**
(`--arch x86_64 --vm-type qemu`) — wolniejsze, ale stabilne. Nie przełączaj na Rosettę.

### 4. SteamCMD: `Info request for AppId 896660 returned error Timeout` / `Failed to download`
Najczęściej **przejściowe** (flaky metadane Steam) — nie panikuj, wymuś ponowienie:
```bash
docker exec valheim supervisorctl restart valheim-updater
```
Updater i tak ponawia sam co 15 min. Jeśli powtarza się uparcie — sprawdź łączność (powinno być
`Connecting anonymously to Steam Public... OK`); jeśli to widać, to nie sieć tylko chwilowy Steam.

### 5. Restart serwera trwa ~7 minut
Domyślnie obraz re-weryfikuje (`validate`) całe ~1,7 GB plików przy każdym starcie — pod QEMU to
kilka minut. W tym projekcie wyłączone przez `STEAMCMD_ARGS: ""` w `docker-compose.yml`
→ restart spada do ~2-3 min. Jeśli edytowałeś compose, upewnij się, że ta linia tam jest.

### 6. „Failed to connect" w grze, BEZ pytania o hasło
Prompt o hasło pojawia się dopiero PO nawiązaniu połączenia. „Failed to connect" bez niego = klient
nie dogadał się z serwerem. Najczęstsze przyczyny:
- **Serwer jeszcze nie gotowy** — przy PIERWSZYM świecie generacja mapy pod QEMU trwa **20+ min**
  (log stoi na `Generating locations` / `Failed to place all X` — to NORMALNE komunikaty, nie błędy;
  CPU ~120% = pracuje). Do końca generacji serwer NIE przyjmuje graczy. Poczekaj na `Opened Steam server`.
- **Łączysz się złym adresem** — użyj **IPv4 z Tailscale** (`100.x.y.z`), z portem `:2456`, przez
  „Join IP". NIE krótkiej nazwy hosta (nie działa między tailnetami), NIE IPv6.
- **Crossplay** — trzymaj wyłączony (patrz #9).

> Tip: pierwsza generacja jest jednorazowa. Import gotowego świata (`./scripts/import-world.sh`) ją POMIJA.

### 7. Brak linii `listening on UDP port 2456` w logach
Ta wersja serwera tego nie loguje. Sygnał gotowości to **`Opened Steam server`**, a potem cykliczny
heartbeat `Connections X ZDOS:Y sent:Z recv:W` (co ~10 min). `./scripts/status.sh` to sprawdza.

### 8. Pusty serwer bierze ~50% CPU (albo ~1,2 rdzenia na Macu)
Normalne. Valheim symuluje świat non-stop nawet bez graczy (~25-30% rdzenia natywnie), a QEMU to
podbija (~1,2 z rdzeni Maca). To nie wyciek. `./scripts/stop.sh` ubija VM → 0% CPU, Mac może spać.
Trzymaj Maca na zasilaniu podczas sesji (bateria + emulacja = grzanie/drenaż).

### 9. Crossplay psuje połączenie przez Tailscale
Crossplay kieruje ruch przez relay PlayFab (brak portu nasłuchu), co potrafi się wykładać za VPN/NAT.
Trzymaj **crossplay wyłączony** (`SERVER_PUBLIC=false`, bez `-crossplay`) — wtedy idzie czyste
połączenie Steam po Tailscale. Wszyscy gracze muszą mieć Valheima na **Steamie**.

### 10. Tailscale: udostępniać znajomym czy zapraszać?
**Udostępniaj WĘZEŁ (Share), nie zapraszaj jako userów.** Zaproszenie wpuszcza ich do CAŁEGO Twojego
tailnetu (w tym np. Home Assistant); Share daje dostęp tylko do węzła z serwerem.
- Panel → Machines → `valheim-server` → ⋯ → **Share** → link dla każdego.
- Tam samo: **Disable key expiry** dla węzła (żeby nie wylogował się między sesjami).
- Domyślny ACL przepuszcza porty gry (2456-2457) dla udostępnionych — nic nie konfigurujesz.
- Znajomi łączą się po `100.x.y.z:2456` (IPv4 z Tailscale).

### 11. Mac zasypia podczas gry
`play.sh` uruchamia `caffeinate` — działa przy **otwartej klapie / na zasilaniu**. Zamknięta klapa:
```bash
sudo pmset -c disablesleep 1     # przed sesją (cofnij: sudo pmset -c disablesleep 0)
```
Trzymaj na zasilaniu. Uwaga: serwer działa tylko gdy Mac jest **zalogowany** (Colima/docker chodzą
w sesji użytkownika) — samo wybudzenie z ekranem logowania nie wystarczy.

### 12. Świat zniknął / chcę wgrać świat ze starej gry
Świat żyje w wolumenie `valheim-config` (`/config/worlds_local` w kontenerze), przeżywa restarty.
Import istniejącego świata (oba pliki o tej samej nazwie):
```bash
./scripts/import-world.sh ~/Downloads/Świat.db ~/Downloads/Świat.fwl
```
Backupy świata: `./scripts/backup.sh` → `./backups/` (robi to też `stop.sh`).

### 13. Reset od zera
```bash
./scripts/stop.sh
colima delete valheim --force     # kasuje VM (świat ginie, jeśli nie masz backupu!)
./scripts/setup.sh
```
