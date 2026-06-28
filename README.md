<img width="1664" height="986" alt="4" src="https://github.com/user-attachments/assets/99fe1174-37b4-4215-9767-b4f57da7c55a" />
<img width="1660" height="1172" alt="3" src="https://github.com/user-attachments/assets/04f96ea2-eb3e-4b05-8f95-31490dbfd308" />
<img width="1670" height="901" alt="2" src="https://github.com/user-attachments/assets/88fecc6a-5bcb-40fd-9a41-de2cf122e460" />
<img width="1679" height="779" alt="1" src="https://github.com/user-attachments/assets/696ac6dc-0758-4dac-a9ca-e675210324d2" />
# VideoVault

**Videoverwaltungs und Archivierungsplattform, von Blink-Überwachungskameras und importiert deren Aufzeichnungen automatisch**  
Ubuntu 24.04 · Multi-Arch: `amd64` + `arm64` (Raspberry Pi 5)

VideoVault ist eine selbst gehostete Plattform zur Verwaltung, Archivierung und Wiedergabe von Videoaufnahmen. Das kombinierte Docker-Image enthält Frontend (nginx) und Backend (Node.js) in einem Container. Optionale Blink-Kameraintegration, NAS-Synchronisation und Live-Stream-Unterstützung sind eingebaut.

Das System verbindet sich mit Blink-Überwachungskameras und importiert deren Aufzeichnungen automatisch. Zusätzlich können Videos manuell hochgeladen werden. Alle Aufnahmen werden nach Jahr/Monat/Tag archiviert und sind über eine übersichtliche Weboberfläche abrufbar.

---

## Schnellstart

```bash
# 1. Dateien in ein Verzeichnis legen
#    docker-compose.yml · init.sql · .env.example · setup.sh

# 2. Konfiguration anpassen
cp .env.example .env
nano .env          # mindestens ADMIN_PASSWORD, DB_PASSWORD, JWT_SECRET setzen

# 3. Starten
chmod +x setup.sh
./setup.sh
```

Webinterface: `http://<host>:8088`

---

## Projektstruktur

```
.
├── docker-compose.yml   # Stack-Definition (PostgreSQL + VideoVault)
├── init.sql             # Vollständiges Datenbankschema (automatisch beim ersten Start)
├── .env.example         # Beispielkonfiguration (nach .env kopieren)
└── setup.sh             # Einmaliger Neustart-Helfer (löscht DB-Volume, startet neu)
```

---

## Konfiguration (.env)

| Variable | Pflicht | Beschreibung |
|---|---|---|
| `ADMIN_PASSWORD` | ✅ | Passwort des Admin-Kontos |
| `DB_PASSWORD` | ✅ | PostgreSQL-Passwort |
| `JWT_SECRET` | ✅ | JWT-Signaturschlüssel (min. 32 Zeichen) |
| `BLINK_ENC_KEY` | – | AES-256-GCM-Schlüssel für Blink-Zugangsdaten (64 Hex-Zeichen). Nach dem ersten Start **nicht mehr ändern**! |
| `WEB_PORT` | – | Externer Port (Standard: `8088`) |
| `MEDIA_VOLUME` | – | Pfad oder Volume-Name für Mediendateien |
| `RETENTION_DAYS` | – | Aufbewahrungsdauer in Tagen (Standard: `90`) |
| `SYNC_ENABLED` | – | HDD-Synchronisation aktivieren (`true`/`false`) |

Schlüssel generieren:
```bash
openssl rand -hex 32      # BLINK_ENC_KEY
openssl rand -base64 48   # JWT_SECRET
```

---

## Persistente Daten

**Modus A – Docker-Volumes (Standard):**
```env
MEDIA_VOLUME=media_data
THUMB_VOLUME=thumb_data
TRASH_VOLUME=trash_data
CONFIG_VOLUME=config_data
```

**Modus B – Host-Verzeichnisse (Bind Mounts):**
```env
MEDIA_VOLUME=/mnt/nas/videovault/media
THUMB_VOLUME=/opt/videovault/thumbnails
TRASH_VOLUME=/opt/videovault/trash
CONFIG_VOLUME=/opt/videovault/config
```

Beide Modi können gemischt werden. Absolute Pfade (beginnend mit `/`) werden automatisch als Bind Mounts behandelt.

---

## Datenbankschema

Das Schema wird beim ersten Start automatisch aus `init.sql` angelegt:

| Tabelle | Beschreibung |
|---|---|
| `users` | Benutzer & Rollen (`admin`, `operator`, `reader`) |
| `videos` | Videoarchiv mit Volltext-Suche |
| `cameras` | Kameraquellen inkl. Blink-Integration |
| `categories` / `tags` | Klassifizierung |
| `blink_account` | Blink-Kontoverknüpfung (verschlüsselt) |
| `blink_clips` | Importierte Blink-Clips |
| `sync_jobs` | Geplante Aufgaben (Cron) |
| `nas_targets` | NAS-Ziele (SMB/NFS/WebDAV) |
| `network_shares` | Lokale Netzwerkfreigaben |
| `settings` | Laufzeit-Einstellungen |
| `audit_log` | Benutzeraktionen |
| `deletion_log` | Löschprotokoll |
| `migration_log` | Angewendete Backend-Migrationen |

---

## Nützliche Befehle

```bash
# Logs verfolgen
docker compose logs videovault -f

# Datenbank-Shell
docker exec -it Video-Vault-db psql -U videovault -d videovault

# Stack stoppen
docker compose down

# Kompletter Neustart (löscht DB-Volume!)
./setup.sh
```

---

## Images

| Service | Image |
|---|---|
| Backend + Frontend | `codxio/video_vault:latest` |
| PostgreSQL | `codxio/video_vault:postgres-ubuntu` |

---

## Architektur

```
Browser
  │
  ▼
nginx :80  (statisches Frontend + Reverse Proxy)
  │
  ▼ /api/
Node.js :8080  (REST-API, Scheduler, Blink-Integration)
  │
  ▼
PostgreSQL :5432  (internes Netzwerk, kein externer Port)
```
