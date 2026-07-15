# Let's Encrypt via All-Inkl KAS (kasserver)

Dieses Add-on fordert Let's-Encrypt-Zertifikate (auch Wildcards, z. B.
`*.example.com`) per **DNS-01-Challenge** über die KAS-API von All-Inkl an
und erneuert sie automatisch. Es nutzt dazu das Projekt
[fetzerch/kasserver](https://github.com/fetzerch/kasserver), dessen
`kasserver-dns-certbot`-Hook certbot als `--manual-auth-hook` /
`--manual-cleanup-hook` übergeben wird.

## Voraussetzungen

- Home Assistant OS oder Supervised (Add-ons benötigen den Supervisor;
  auf Home Assistant Core allein läuft das **nicht**, dort müsste man
  das Dockerfile manuell als eigenständigen Container betreiben).
- Ein All-Inkl-Zugang mit KAS-API-Zugriff (KAS-Login, das auf
  DNS-Einstellungen zugreifen darf).
- Die Domain(s) müssen bei All-Inkl als DNS-Zone verwaltet werden.

## Installation

1. In Home Assistant: **Einstellungen → Add-ons → Add-on-Store →
   ⋮ (oben rechts) → Repositories** und die URL dieses Repos eintragen.
2. Das Add-on **"Let's Encrypt (All-Inkl KAS / kasserver)"** installieren.
3. Optionen konfigurieren (siehe unten) und starten.

## Konfiguration

```yaml
domains:
  - "example.com"
  - "*.example.com"
email: "du@example.com"
kas_user: "dein-kas-login"
kas_password: "dein-kas-passwort"
staging: false
cert_name: "kasserver"
key_type: "ecdsa"
propagation_seconds: 90
renew_check_interval_hours: 12
auto_restart_core: true
```

| Option | Beschreibung |
|---|---|
| `domains` | Liste der Domains/Wildcards für das Zertifikat |
| `email` | Kontakt-E-Mail für Let's Encrypt (Ablaufwarnungen etc.) |
| `kas_user` / `kas_password` | KAS-Zugangsdaten von All-Inkl |
| `staging` | `true` für Let's-Encrypt-Staging (Testzertifikate, kein Vertrauen im Browser) - zum Testen der Konfiguration ohne Rate-Limits zu riskieren |
| `cert_name` | Name, unter dem certbot und die Ausgabedateien abgelegt werden |
| `key_type` | `rsa` oder `ecdsa` |
| `propagation_seconds` | Wartezeit nach dem Setzen des TXT-Records, bevor certbot validiert (KAS braucht oft etwas länger) |
| `renew_check_interval_hours` | Wie oft im laufenden Betrieb auf Erneuerung geprüft wird |
| `auto_restart_core` | Home Assistant Core automatisch neu starten, wenn sich das Zertifikat geändert hat |

## Ausgabe / Verwendung in Home Assistant

Die Zertifikatsdateien werden nach `/ssl/` kopiert (dieser Ordner ist der
reguläre HA-`/ssl`-Ordner):

- `/ssl/<cert_name>_fullchain.pem`
- `/ssl/<cert_name>_privkey.pem`

In `configuration.yaml`:

```yaml
http:
  ssl_certificate: /ssl/kasserver_fullchain.pem
  ssl_key: /ssl/kasserver_privkey.pem
```

Nach der ersten Zertifikatsausstellung Home Assistant Core einmal neu
starten, damit die Dateien geladen werden (danach übernimmt das Add-on
das automatisch bei jeder Erneuerung, sofern `auto_restart_core: true`).

## Hinweise

- Beim allerersten Start unbedingt `staging: true` testen, um die
  Konfiguration (KAS-Zugangsdaten, Domains, DNS-Propagation) zu prüfen,
  ohne gegen die Rate-Limits der produktiven Let's-Encrypt-API zu laufen.
- Zertifikate und certbot-Zustand liegen persistent unter
  `/data/letsencrypt` innerhalb des Add-ons (überlebt Neustarts/Updates
  des Add-ons).
- Bei Fehlern im Log nach `kasserver`- bzw. `certbot`-Meldungen suchen -
  All-Inkl hat eine Flood-Protection, kasserver wiederholt Anfragen bei
  Bedarf automatisch.
