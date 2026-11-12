#!/usr/bin/env bash
# -------------------------------------------------------------------------
# Zotero -> Obsidian: copy notes and highlights into the vault automatically
# -------------------------------------------------------------------------
# Notes and highlights made in the Zotero iPhone app sync to zotero.org.
# Every 15 minutes this server fetches what changed (read-only key) and
# writes Markdown files into the browser Obsidian's vault, folder Zotero/.
# LiveSync then carries them to Obsidian on the phone.
#
# Run as root (after OBSIDIAN-SYNC.md section 3, so the browser Obsidian has
# a vault that syncs with the phone):
#
#   curl -fsSL https://raw.githubusercontent.com/4b4z7d8txh-lgtm/theflyingcocker/main/zotero-obsidian-setup.sh -o /root/zo-ob-setup.sh && bash /root/zo-ob-setup.sh
#
# 1. Finds the vault in /opt/obsidian/config.
# 2. Asks for the Zotero key (once), checks it with zotero.org and keeps it
#    in /opt/zotero-obsidian/config.json (root only).
# 3. Installs /usr/local/bin/zotero-to-obsidian (from zotero-to-obsidian.py).
# 4. Runs it every 15 minutes (/etc/cron.d/zotero-to-obsidian),
#    log in /var/log/zotero-to-obsidian.log.
# 5. Runs it once now.
#
# Safe to run again: it keeps the key and updates the program.
# New key: rm /opt/zotero-obsidian/config.json, then run the line again.
# See ZOTERO-OBSIDIAN.md.
# -------------------------------------------------------------------------

set -euo pipefail

BASE=https://raw.githubusercontent.com/4b4z7d8txh-lgtm/theflyingcocker/main
DIR=/opt/zotero-obsidian
BIN=/usr/local/bin/zotero-to-obsidian
LOG=/var/log/zotero-to-obsidian.log
OBS=/opt/obsidian/config

step() { echo; echo "=== $* ==="; }
fail() { echo; echo "STOPPED: $*"; echo "Send this output to Claude."; exit 1; }
trap 'fail "the command on line $LINENO of the script failed (see the lines above)"' ERR

echo "zo-ob-setup version: 2026-11-12"
[ "$(id -u)" -eq 0 ] || fail "run this as root"

step "1/5 Find the Obsidian vault"
command -v python3 >/dev/null || fail "python3 isn't installed (apt install -y python3)"
[ -d "$OBS" ] || fail "$OBS doesn't exist - the browser Obsidian isn't set up (SUBDOMAINS.md)"
VAULTS=()
while IFS= read -r -d '' dot; do
  v=$(dirname "$dot")
  case "$v" in */.*) continue ;; esac          # skip Obsidian's own hidden folders
  VAULTS+=("$v")
done < <(find "$OBS" -maxdepth 4 -type d -name .obsidian -print0 2>/dev/null)
OLD_VAULT=""
[ -s "$DIR/config.json" ] && OLD_VAULT=$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1])).get("vault",""))' "$DIR/config.json")
if [ ${#VAULTS[@]} -eq 0 ]; then
  fail "no vault found in $OBS yet. First do OBSIDIAN-SYNC.md section 3 (create a vault in the browser Obsidian and connect LiveSync), then run this again"
elif [ ${#VAULTS[@]} -eq 1 ]; then
  VAULT=${VAULTS[0]}
elif [ -n "$OLD_VAULT" ] && printf '%s\n' "${VAULTS[@]}" | grep -qxF "$OLD_VAULT"; then
  VAULT=$OLD_VAULT
else
  echo "More than one vault found:"
  for i in "${!VAULTS[@]}"; do echo "  $((i+1)). ${VAULTS[$i]}"; done
  read -r -p "Type the number of the vault that syncs with your phone: " N
  [[ "$N" =~ ^[0-9]+$ ]] && [ "$N" -ge 1 ] && [ "$N" -le ${#VAULTS[@]} ] || fail "'$N' isn't one of the numbers"
  VAULT=${VAULTS[$((N-1))]}
fi
echo "vault: $VAULT"
if [ -d "$VAULT/.obsidian/plugins/obsidian-livesync" ]; then
  echo "LiveSync is installed in this vault - good"
else
  echo "WARNING: LiveSync isn't installed in this vault yet, so the notes will"
  echo "         stay on the server until you do OBSIDIAN-SYNC.md section 3."
fi

step "2/5 Install the program"
mkdir -p "$DIR"; chmod 700 "$DIR"
curl -fsSL "$BASE/zotero-to-obsidian.py" -o "$BIN.new" || fail "couldn't download zotero-to-obsidian.py from main (404 = not merged into main yet)"
python3 -m py_compile "$BIN.new" || fail "the downloaded program has an error"
rm -rf "$(dirname "$BIN")/__pycache__"
chmod 755 "$BIN.new"; mv "$BIN.new" "$BIN"
echo "installed $BIN"

step "3/5 Zotero key"
if [ -s "$DIR/config.json" ]; then
  echo "keeping the saved key"
  "$BIN" --setup "$VAULT" || fail "the saved key didn't work (see above). For a new key: rm $DIR/config.json and run this again"
else
  echo "On zotero.org: Settings -> Security -> Create new private key."
  echo "Tick 'Allow library access' and 'Allow notes access' (nothing else), Save Key, copy it."
  read -r -s -p "Paste the key here and press Enter (it stays hidden): " ZO_KEY; echo
  ZO_KEY=$(printf '%s' "$ZO_KEY" | tr -d '[:space:]')
  [ -n "$ZO_KEY" ] || fail "no key was pasted"
  ZO_KEY="$ZO_KEY" "$BIN" --setup "$VAULT" || fail "the key didn't work (see the line above). Run this again to retry"
fi
unset ZO_KEY

step "4/5 Every 15 minutes"
echo "*/15 * * * * root flock -n /run/zotero-to-obsidian.lock $BIN >> $LOG 2>&1" > /etc/cron.d/zotero-to-obsidian
chmod 644 /etc/cron.d/zotero-to-obsidian
cat > /etc/logrotate.d/zotero-to-obsidian <<EOF
$LOG {
  weekly
  rotate 4
  compress
  missingok
  notifempty
}
EOF
echo "scheduled (/etc/cron.d/zotero-to-obsidian)"

step "5/5 First run (a big library can take a few minutes)"
if ! flock /run/zotero-to-obsidian.lock "$BIN" 2>&1 | tee -a "$LOG"; then
  fail "the first run had a problem (see above)"
fi
COUNT=$(find "$VAULT/Zotero" -name '*.md' 2>/dev/null | wc -l)

echo
echo "================ ALL DONE ================"
echo "$COUNT note file(s) in $VAULT/Zotero"
echo "Phone: open Obsidian, wait a minute, look in the Zotero folder."
echo "From now on new notes and highlights arrive within about 15 minutes."
echo "Log: tail -n 20 $LOG"
echo "=========================================="
