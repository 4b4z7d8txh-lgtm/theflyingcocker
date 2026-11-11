#!/usr/bin/env bash
# -------------------------------------------------------------------------
# Zotero in the browser at https://zo.theflyingcocker.co.uk/app/
# -------------------------------------------------------------------------
# The same idea as the vault (ob.../app/): the real Zotero desktop program
# runs in Docker on the server (linuxserver/zotero) and is shown in a browser
# tab. Members only, through the normal website sign-in.
#
# Run as root, AFTER zotero-webdav-setup.sh (zo. must already be live):
#
#   curl -fsSL https://raw.githubusercontent.com/4b4z7d8txh-lgtm/theflyingcocker/main/zotero-web-setup.sh -o /root/zo-web-setup.sh && bash /root/zo-web-setup.sh
#
# 1. Starts the container "zotero-web" on 127.0.0.1:3010 only
#    (settings and Zotero's data in /opt/zotero-web/config).
# 2. Adds /app/ to the zo. nginx site via the snippet
#    /etc/nginx/snippets/fc-zotero-app.conf (members gate stays on).
# 3. Deploys the updated landing page (with the "Open the library" button).
#
# Safe to run again. See ZOTERO-SYNC.md section 7 for the first sign-in.
# -------------------------------------------------------------------------

set -euo pipefail

HOST=zo.theflyingcocker.co.uk
DIR=/opt/zotero-web
CONTAINER=zotero-web
IMAGE=lscr.io/linuxserver/zotero:latest
PORT=3010
SITE=/etc/nginx/sites-available/$HOST
SNIPPET=/etc/nginx/snippets/fc-zotero-app.conf
WEBROOT=/var/www/zo
BASE=https://raw.githubusercontent.com/4b4z7d8txh-lgtm/theflyingcocker/main

step() { echo; echo "=== $* ==="; }
fail() { echo; echo "STOPPED: $*"; echo "Send this output to Claude."; exit 1; }
trap 'fail "the command on line $LINENO of the script failed (see the lines above)"' ERR

echo "zo-web-setup version: 2026-11-11"
[ "$(id -u)" -eq 0 ] || fail "run this as root"

step "1/5 Checks"
command -v docker >/dev/null || fail "Docker isn't installed"
docker compose version >/dev/null 2>&1 || fail "docker compose isn't installed (apt install -y docker-compose-v2)"
[ -e "$SITE" ] || fail "$SITE is missing - run zotero-webdav-setup.sh first"
grep -q "listen.*443" "$SITE" || fail "$SITE has no HTTPS yet - run zotero-webdav-setup.sh first"
[ -e /etc/nginx/snippets/fc-admin-gate.conf ] || fail "the members gate snippet is missing"
if [ "$(docker inspect -f '{{.State.Running}}' "$CONTAINER" 2>/dev/null || echo no)" != true ] \
   && ss -ltn "sport = :$PORT" | grep -q LISTEN; then
  fail "port $PORT is already used by another program: $(ss -ltnp "sport = :$PORT" | tail -n +2)"
fi
free -h | sed -n '1,2p'
AVAIL_MB=$(awk '/MemAvailable/ {print int($2/1024)}' /proc/meminfo)
if [ "$AVAIL_MB" -lt 800 ] && [ "$(docker inspect -f '{{.State.Running}}' "$CONTAINER" 2>/dev/null || echo no)" != true ]; then
  fail "only ${AVAIL_MB} MB of memory is free; Zotero in the browser needs about 800 MB. Nothing was changed"
fi
echo "checks OK (${AVAIL_MB} MB memory free)"

step "2/5 Start Zotero in Docker (first download takes a few minutes)"
mkdir -p "$DIR/config"
cat > "$DIR/compose.yaml" <<EOF
# Zotero in the browser (written by zotero-web-setup.sh - edits are overwritten).
services:
  zotero:
    image: $IMAGE
    container_name: $CONTAINER
    restart: unless-stopped
    ports:
      - "127.0.0.1:$PORT:3000"        # only reachable through nginx (members only)
    environment:
      - PUID=1000
      - PGID=1000
      - TZ=Europe/London
      - SUBFOLDER=/app/
      - TITLE=Library
    volumes:
      - ./config:/config
    shm_size: "1gb"
    mem_limit: 2g                     # so it can't starve the other services
    security_opt:
      - seccomp:unconfined
    logging:
      driver: json-file
      options:
        max-size: "1m"
        max-file: "3"
EOF
cd "$DIR"
docker compose up -d --quiet-pull || fail "Zotero did not start (Docker Hub may be busy - wait a few minutes and run this again)"
OK=""; CODE=""
for i in $(seq 1 60); do
  CODE=$(curl -s -o /dev/null -w "%{http_code}" "http://127.0.0.1:$PORT/app/" || true)
  case "$CODE" in 200|301|302) OK=1; break ;; esac
  sleep 2
done
[ -n "$OK" ] || { docker logs --tail 30 "$CONTAINER" || true; fail "Zotero isn't answering on 127.0.0.1:$PORT (got $CODE)"; }
echo "Zotero is running"

step "3/5 nginx: add /app/ to $HOST"
cat > "$SNIPPET" <<EOF
# Zotero in the browser (linuxserver/zotero in Docker). Members only: the
# members gate from the site stays on. Installed by zotero-web-setup.sh.
location = /app { return 301 /app/; }
location /app/ {
    proxy_pass http://127.0.0.1:$PORT;
    proxy_http_version 1.1;
    proxy_set_header Upgrade \$http_upgrade;
    proxy_set_header Connection "upgrade";
    proxy_set_header Host \$host;
    proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
    proxy_set_header X-Forwarded-Proto \$scheme;
    proxy_buffering off;
    proxy_read_timeout 86400s;
    client_max_body_size 200m;
}
EOF
BACKUP=/root/zo-site-before-web.conf
if grep -q "fc-zotero-app.conf" "$SITE"; then
  echo "site already includes the snippet"
  CHANGED=""
else
  grep -q "include snippets/fc-zotero-dav.conf;" "$SITE" || fail "couldn't find where to add /app/ in $SITE"
  cp "$SITE" "$BACKUP"
  sed -i 's|^\([[:space:]]*\)include snippets/fc-zotero-dav.conf;.*$|&\n\1include snippets/fc-zotero-app.conf;      # Zotero in the browser at /app/ (members only)|' "$SITE"
  CHANGED=1
  echo "snippet added (old file saved as $BACKUP)"
fi
if ! nginx -t; then
  [ -n "$CHANGED" ] && cp "$BACKUP" "$SITE"
  nginx -t && systemctl reload nginx || true
  fail "nginx check failed - the zo. site was put back as it was"
fi
systemctl reload nginx
echo "nginx reloaded"

step "4/5 Landing page"
mkdir -p "$WEBROOT/assets"
curl -fsSL "$BASE/subdomains/zo/index.html"      -o "$WEBROOT/index.html"
curl -fsSL "$BASE/subdomains/shared/landing.css" -o "$WEBROOT/assets/landing.css"
chown -R deployuser:www-data "$WEBROOT"
find "$WEBROOT" -type d -exec chmod 755 {} \;
find "$WEBROOT" -type f -exec chmod 644 {} \;
echo "landing page deployed"

step "5/5 Test"
sleep 1
CODE=$(curl -s -o /dev/null -w "%{http_code}" "https://$HOST/app/" || true)
[ "$CODE" = 302 ] || fail "https://$HOST/app/ isn't behind the members login (got $CODE)"
CODE=$(curl -s -o /dev/null -w "%{http_code}" -X PROPFIND "https://$HOST/dav/zotero/" || true)
[ "$CODE" = 401 ] || fail "the file sync at /dav/ changed (got $CODE instead of 401)"
echo "/app/ is members-only, /dav/ still has its own password"

echo
echo "================================================================"
echo " ALL DONE. Sign in on www.theflyingcocker.co.uk, open Library,"
echo " then 'Open the library'. The first time, inside that Zotero:"
echo "   Edit > Settings > Sync: sign in with your zotero.org account,"
echo "   File Syncing: WebDAV, https:// zo.theflyingcocker.co.uk/dav"
echo "   username zotero, password from:"
echo "     cat /opt/zotero-webdav/credentials.txt"
echo "   Verify Server, then press the green sync arrow."
echo "================================================================"
