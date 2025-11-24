#!/bin/bash
# Script to remove ghost "Music Assistant Mobile" players from Music Assistant

set -e

SETTINGS_FILE="/home/home-server/docker/music-assistant/data/settings.json"
BACKUP_FILE="/home/home-server/docker/music-assistant/data/settings.json.pre-cleanup-backup"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo -e "${YELLOW}=== Music Assistant Ghost Player Cleanup ===${NC}"
echo ""

# Check if settings file exists
if [ ! -f "$SETTINGS_FILE" ]; then
    echo -e "${RED}Error: Settings file not found at $SETTINGS_FILE${NC}"
    exit 1
fi

# Check if jq is installed
if ! command -v jq &> /dev/null; then
    echo -e "${RED}Error: jq is not installed. Install with: sudo apt install jq${NC}"
    exit 1
fi

# Count ghost players before cleanup
GHOST_COUNT=$(cat "$SETTINGS_FILE" | jq '[.players | to_entries[] | select(.value.default_name == "Music Assistant Mobile")] | length')

echo -e "Found ${RED}$GHOST_COUNT${NC} ghost \"Music Assistant Mobile\" players"
echo ""

if [ "$GHOST_COUNT" -eq 0 ]; then
    echo -e "${GREEN}No ghost players to remove!${NC}"
    exit 0
fi

# List the ghost players
echo "Ghost players to be removed:"
cat "$SETTINGS_FILE" | jq -r '.players | to_entries[] | select(.value.default_name == "Music Assistant Mobile") | "  - " + .key'
echo ""

# Ask for confirmation
read -p "Do you want to remove these players? (yes/no): " CONFIRM

if [ "$CONFIRM" != "yes" ]; then
    echo -e "${YELLOW}Cleanup cancelled.${NC}"
    exit 0
fi

# Create backup
echo ""
echo -e "${YELLOW}Creating backup...${NC}"
cp "$SETTINGS_FILE" "$BACKUP_FILE"
echo -e "${GREEN}Backup created at: $BACKUP_FILE${NC}"

# Remove ghost players
echo ""
echo -e "${YELLOW}Removing ghost players...${NC}"

# Get list of ghost player IDs
GHOST_IDS=$(cat "$SETTINGS_FILE" | jq -r '.players | to_entries[] | select(.value.default_name == "Music Assistant Mobile") | .key')

# Remove each ghost player from settings
for player_id in $GHOST_IDS; do
    echo "  Removing: $player_id"
done

# Use jq to filter out ghost players
cat "$SETTINGS_FILE" | jq '.players |= with_entries(select(.value.default_name != "Music Assistant Mobile"))' > "${SETTINGS_FILE}.tmp"
mv "${SETTINGS_FILE}.tmp" "$SETTINGS_FILE"

# Verify cleanup
REMAINING=$(cat "$SETTINGS_FILE" | jq '[.players | to_entries[] | select(.value.default_name == "Music Assistant Mobile")] | length')

echo ""
if [ "$REMAINING" -eq 0 ]; then
    echo -e "${GREEN}✓ Successfully removed all $GHOST_COUNT ghost players!${NC}"
else
    echo -e "${RED}Warning: $REMAINING ghost players still remain${NC}"
fi

echo ""
echo -e "${YELLOW}Next steps:${NC}"
echo "1. Restart Music Assistant: docker restart music_assistant"
echo "2. Or: cd /home/home-server/docker/music-assistant && docker compose restart"
echo ""
echo -e "${YELLOW}To restore backup if needed:${NC}"
echo "cp $BACKUP_FILE $SETTINGS_FILE"
echo "Then restart Music Assistant"
