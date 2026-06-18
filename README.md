# Valheim — prywatny serwer na Macu (Apple Silicon) przez Tailscale

Postaw dedykowany serwer Valheim dla paczki znajomych na **MacBooku/Macu z M-serią**, za **0 zł**,
**bez publicznego IP i bez port-forwardingu**. Gracie na żądanie, znajomi łączą się przez Tailscale.
Wszystko oskryptowane: jedna komenda start, jedna stop.

> Stan: **działa**, przetestowane na MacBooku Pro M1 / macOS 26. Dla 3 graczy spokojnie wystarcza.

---

## Dlaczego tak (architektura)

Dedykowany serwer Valheim istnieje **wyłącznie jako binarka x86_64** (Linux/Windows) — nie ma builda
na ARM ani na macOS. Na Apple Silicon trzeba go więc emulować. Sprawdzone, stabilne podejście:

```
[Mac M1] → [VM x86_64, pełny QEMU (Colima)] → Docker:
                                                ├─ tailscale  (węzeł "valheim-server", IP 100.x)
                                                └─ valheim    (lloesche/valheim-server, sieć współdzielona z tailscale)

  znajomy z Tailscale ──WireGuard──▶ 100.x.y.z : 2456
```

- **Colima + pełny QEMU**, nie Docker Desktop + Rosetta — Rosetta crashuje silnik mono/Unity tego
  serwera. Pełny QEMU jest wolniejszy, ale działa stabilnie.
- **Sidecar Tailscale** — serwer współdzieli sieć z kontenerem Tailscale (`network_mode: service:tailscale`),
  więc jest widoczny pod adresem `100.x` węzła. **Nie publikujemy żadnych portów na hosta** → omija to
  buga UDP w Docker Desktop na macOS i nie wymaga port-forwardingu na routerze.
- **Obraz** [`lloesche/valheim-server`](https://github.com/lloesche/valheim-server-docker) — daje
  auto-update serwera, cykliczne backupy świata i opcjonalne mody „z pudełka".

## Wymagania

- Mac z **Apple Silicon** (M1/M2/M3/M4), macOS 13+ (testowane na 26). Min. **8 GB RAM**, ~10 GB dysku.
- **[Homebrew](https://brew.sh)**.
- Konto **[Tailscale](https://tailscale.com)** (darmowy plan wystarcza: 6 userów / nielimit urządzeń).
- Wszyscy gracze mają **Valheima na Steamie** (crossplay jest wyłączony — patrz niżej).

## Szybki start

```bash
git clone <to-repo> valheim-server && cd valheim-server

./scripts/bootstrap.sh           # 1. instaluje colima, qemu, lima-additional-guestagents, docker
cp .env.example .env             # 2. (bootstrap robi to sam, jeśli brak)
$EDITOR .env                     #    uzupełnij: SERVER_NAME, SERVER_PASS (min. 5 zn.), TS_AUTHKEY
./scripts/doctor.sh              # 3. sprawdzenie gotowości
./scripts/setup.sh               # 4. postawienie (PIERWSZY raz ~15+ min: emuluje x86 Ubuntu + pobiera serwer)
```

**Auth key Tailscale:** wygeneruj na <https://login.tailscale.com/admin/settings/keys> →
„Generate auth key" → zaznacz **Reusable**, zostaw **Ephemeral wyłączone** → wklej do `.env` jako `TS_AUTHKEY`.

Po `setup.sh` adres serwera pokaże `./scripts/status.sh`. W panelu Tailscale **wyłącz wygasanie klucza**
węzła `valheim-server` (Machines → ⋯ → Disable key expiry), żeby nie wylogował się między sesjami.

## Skrypty

| Skrypt | Do czego |
|---|---|
| `scripts/bootstrap.sh` | jednorazowo: instaluje wszystkie zależności (Homebrew) |
| `scripts/doctor.sh` | preflight: sprawdza narzędzia + `.env` (nic nie zmienia) |
| `scripts/setup.sh` | jednorazowo: tworzy VM x86_64 (QEMU) i podnosi serwer + Tailscale |
| `scripts/play.sh` | **start sesji** — VM + serwer + Mac nie zaśnie (jedna komenda) |
| `scripts/stop.sh` | **koniec sesji** — backup + stop serwera + stop VM (Mac może spać) |
| `scripts/status.sh` | co działa + adres dla znajomych |
| `scripts/logs.sh` | logi serwera na żywo |
| `scripts/backup.sh` | zrzut świata na dysk Maca (opcjonalnie na Google Drive) |
| `scripts/update.sh` | aktualizacja obrazu kontenera |
| `scripts/import-world.sh` | wgranie istniejącego świata (`.db` + `.fwl`) |

Na co dzień: **`./scripts/play.sh`** gdy gracie, **`./scripts/stop.sh`** gdy koniec.

## Jak łączą się znajomi

1. Instalują Tailscale i logują się na **swoje** konto.
2. **Udostępniasz im węzeł** (NIE zapraszasz do sieci — patrz „Bezpieczeństwo"): panel Tailscale →
   **Machines → `valheim-server` → ⋯ → Share** → wyślij link każdemu. Akceptują.
3. Adres podaje `./scripts/status.sh`. W grze: **Start Game → Join Game → Join IP** → `100.x.y.z:2456` + hasło.

> Serwer jest prywatny (`SERVER_PUBLIC=false`) — nie pojawia się na liście, tylko „Join IP".

## Import świata

Poproś o **oba** pliki (ta sama nazwa bazowa): `<Świat>.db` i `<Świat>.fwl`
(Windows: `%USERPROFILE%\AppData\LocalLow\IronGate\Valheim\worlds_local\`). Potem:
```bash
./scripts/import-world.sh ~/Downloads/Świat.db ~/Downloads/Świat.fwl
```
Skrypt skopiuje świat, ustawi `WORLD_NAME` w `.env` i zrestartuje serwer. Import gotowego świata
**pomija** wolną pierwszą generację mapy.

## Backupy

- Obraz robi cykliczne zip-backupy świata (`BACKUPS_CRON` w compose).
- `./scripts/backup.sh` zrzuca je na Maca do `./backups/` (+ żywy świat jako zapas). `stop.sh` robi to automatycznie.
- Chmura: ustaw `GDRIVE_DIR` w `.env` na folder w zsynchronizowanym Google Drive.
- Retencja: obraz trzyma 12 backupów w kontenerze, `backup.sh` 30 na Macu (celowo różne).
- **Auto-backup co 30 min (opcjonalnie)** — `~/Library/LaunchAgents/com.valheim.backup.plist`:
  ```xml
  <?xml version="1.0" encoding="UTF-8"?>
  <plist version="1.0"><dict>
    <key>Label</key><string>com.valheim.backup</string>
    <key>ProgramArguments</key>
    <array><string>/bin/zsh</string><string>-c</string>
      <string>cd "$HOME/valheim-server" && ./scripts/backup.sh</string></array>
    <key>StartInterval</key><integer>1800</integer>
    <key>StandardErrorPath</key><string>/tmp/valheim-backup.err</string>
  </dict></plist>
  ```
  Załaduj: `launchctl load ~/Library/LaunchAgents/com.valheim.backup.plist` (backup działa tylko gdy serwer chodzi).

## Aktualizacje

- Serwer Valheim **auto-aktualizuje się sam** co 15 min, gdy nikt nie gra. `./scripts/update.sh`
  aktualizuje obraz kontenera (rzadziej potrzebne).
- **Przed sesją** dogadajcie w paczce „aktualizujcie klienty" — serwer i gracze muszą być na tej samej
  wersji Valheima, inaczej „Incompatible version".

## Zdalne zarządzanie (opcjonalnie)

Żeby odpalać serwer spoza domu: zainstaluj Tailscale na samym Macu, włącz **System Settings → General →
Sharing → Remote Login**, i z dowolnego urządzenia w tailnecie: `ssh user@<tailscale-IP-Maca>` →
`cd ~/valheim-server && ./scripts/play.sh`.

## Mac nie może spać podczas gry

`play.sh` uruchamia `caffeinate` (działa przy otwartej klapie / na zasilaniu). Zamknięta klapa:
`sudo pmset -c disablesleep 1` przed sesją (`...disablesleep 0` po). Trzymaj Maca na zasilaniu.
Serwer działa tylko gdy Mac jest **zalogowany** (Colima/docker w sesji użytkownika).

## Czego się spodziewać (wydajność)

- To **emulacja** — pierwsza generacja świata pod QEMU jest wolna (~20+ min, **jednorazowo**;
  import gotowego świata ją pomija). Samo granie jest dużo lżejsze.
- Pusty serwer bierze ~1 rdzeń Maca (cecha Valheima + narzut QEMU) — znika do 0 po `stop.sh`.
- Dla ~3 casualowych graczy zapas jest spory. To **nie** serwer 24/7 — Mac musi być wybudzony i zalogowany.

## Bezpieczeństwo

- **Sekrety nie idą do repo:** `.env` (hasło, `TS_AUTHKEY`) jest w `.gitignore`. Commituj tylko `.env.example`.
- **Share węzła, nie zaproszenie usera:** zaproszenie do tailnetu daje znajomym dostęp do CAŁEJ Twojej
  sieci (np. Home Assistant); Share — tylko do węzła z serwerem.

## Problemy?

Zobacz **[TROUBLESHOOTING.md](TROUBLESHOOTING.md)** — zebrane realne pułapki (brak agenta x86_64, timeouty
SteamCMD, „failed to connect" podczas generacji, wolny restart, idle CPU, Tailscale share vs invite, ...).

## Podziękowania

[lloesche/valheim-server-docker](https://github.com/lloesche/valheim-server-docker) ·
[Colima](https://github.com/abiosoft/colima) · [Lima](https://github.com/lima-vm/lima) ·
[Tailscale](https://tailscale.com) · Iron Gate (Valheim).

## Licencja

MIT — patrz [LICENSE](LICENSE).
