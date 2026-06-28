#!/bin/bash
# =============================================================================
#  VideoVault – Setup-Script
#  Führt einen sauberen Neustart durch:
#  1. Stack stoppen
#  2. DB-Volume löschen (Schema wird neu angelegt)
#  3. Stack starten
#
#  Verwendung:
#    chmod +x setup.sh
#    ./setup.sh
#
#  WARNUNG: Löscht alle Datenbankdaten (Videos, Benutzer, Einstellungen).
#  Mediendateien auf den Volumes bleiben erhalten.
# =============================================================================

set -e

COMPOSE_FILE="docker-compose.yml"
DB_VOLUME="videovault_db_data"

# Farben
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

echo -e "${YELLOW}VideoVault Setup${NC}"
echo "=================================================="

# Prüfen ob .env existiert
if [ ! -f ".env" ]; then
    if [ -f ".env.example" ]; then
        echo -e "${YELLOW}Keine .env gefunden – kopiere .env.example ...${NC}"
        cp .env.example .env
        echo -e "${RED}WICHTIG: .env anpassen bevor du fortfährst!${NC}"
        echo "  nano .env"
        exit 1
    else
        echo -e "${RED}Fehler: Keine .env und keine .env.example gefunden.${NC}"
        exit 1
    fi
fi

# Prüfen ob init.sql existiert
if [ ! -f "init.sql" ]; then
    echo -e "${RED}Fehler: init.sql nicht gefunden.${NC}"
    exit 1
fi

echo -e "${YELLOW}Stack wird gestoppt ...${NC}"
docker compose -f "$COMPOSE_FILE" down

# DB-Volume löschen
if docker volume inspect "$DB_VOLUME" &>/dev/null; then
    echo -e "${YELLOW}DB-Volume '$DB_VOLUME' wird gelöscht ...${NC}"
    docker volume rm "$DB_VOLUME"
    echo -e "${GREEN}Volume gelöscht.${NC}"
else
    echo "DB-Volume nicht vorhanden – wird neu angelegt."
fi

echo -e "${YELLOW}Stack wird gestartet ...${NC}"
docker compose -f "$COMPOSE_FILE" up -d

echo ""
echo -e "${GREEN}=================================================="
echo " VideoVault gestartet!"
echo "=================================================="
echo -e "${NC}"
echo "Logs verfolgen:  docker compose logs videovault -f"
echo "Webinterface:    http://$(hostname -I | awk '{print $1}'):$(grep WEB_PORT .env | cut -d= -f2 || echo 8088)"
