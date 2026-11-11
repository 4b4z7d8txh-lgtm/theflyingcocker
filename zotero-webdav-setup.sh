#!/usr/bin/env bash
# -------------------------------------------------------------------------
# Zotero file sync (WebDAV) on zo.theflyingcocker.co.uk
# -------------------------------------------------------------------------
# Zotero keeps syncing the library (items, notes, tags) through zotero.org.
# This gives it somewhere of our own to keep the attachment FILES (PDFs etc.).
# Run as root, after adding the DNS record for zo.:
#
#   curl -fsSL https://raw.githubusercontent.com/4b4z7d8txh-lgtm/theflyingcocker/main/zotero-webdav-setup.sh -o /root/zo-setup.sh && bash /root/zo-setup.sh
#
# 1. Runs a small WebDAV server in Docker (hacdias/webdav), on 127.0.0.1:8090
#    only, with one account "zotero" and a long random password.
#    Everything lives in /opt/zotero-webdav (files in ./data/zotero).
# 2. nginx site zo.theflyingcocker.co.uk:
#      /      landing page, members only (website sign-in)
#      /dav/  the WebDAV folder (its own username/password, as the Zotero
#             app can't use the website sign-in)
#    plus an HTTPS certificate from Let's Encrypt.
# 3. Nightly backup at 03:30 into /root/backups/zotero (30 days).
#
# Safe to run again: it keeps the same password and files.
# See ZOTERO-SYNC.md for the Zotero settings on each device.
# -------------------------------------------------------------------------

set -euo pipefail

HOST=zo.theflyingcocker.co.uk
DIR=/opt/zotero-webdav
CREDS=$DIR/credentials.txt
IMAGE=hacdias/webdav:v5.17.1
CONTAINER=zotero-webdav
PORT=8090
RUN_AS=65534:65534                 # "nobody": the WebDAV server never runs as root
SITE=/etc/nginx/sites-available/$HOST
SNIPPET=/etc/nginx/snippets/fc-zotero-dav.conf
WEBROOT=/var/www/zo
BASE=https://raw.githubusercontent.com/4b4z7d8txh-lgtm/theflyingcocker/main
DAV_URL=https://$HOST/dav
DAV_USER=zotero

step() { echo; echo "=== $* ==="; }
fail() { echo; echo "STOPPED: $*"; echo "Send this output to Claude."; exit 1; }
trap 'fail "the command on line $LINENO of the script failed (see the lines above)"' ERR

echo "zo-setup version: 2026-11-11"
[ "$(id -u)" -eq 0 ] || fail "run this as root"

step "1/7 Checks"
command -v docker >/dev/null || fail "Docker isn't installed (see SUBDOMAINS.md step 4)"
docker compose version >/dev/null 2>&1 || fail "docker compose isn't installed (apt install -y docker-compose-v2)"
command -v nginx >/dev/null || fail "nginx isn't installed"
command -v certbot >/dev/null || fail "certbot isn't installed"
[ -e /etc/nginx/snippets/fc-admin-gate.conf ] || fail "the members gate snippet is missing (SUBDOMAINS.md step 3)"
apt-get install -y -q rsync >/dev/null
DNS_IP=$(getent ahostsv4 "$HOST" | awk 'NR==1{print $1}' || true)
[ -n "$DNS_IP" ] || fail "$HOST doesn't exist in DNS yet. Add an A record 'zo' pointing at this server, wait 10 minutes, then run this again"
MY_IPS="$(hostname -I 2>/dev/null) $(curl -4 -fsS --max-time 10 https://api.ipify.org 2>/dev/null || true)"
case " $MY_IPS " in
  *" $DNS_IP "*) echo "DNS OK: $HOST -> $DNS_IP" ;;
  *) fail "$HOST points at $DNS_IP, but this server is: $MY_IPS. Fix the 'zo' A record, then run this again" ;;
esac
if [ "$(docker inspect -f '{{.State.Running}}' "$CONTAINER" 2>/dev/null || echo no)" != true ] \
   && ss -ltn "sport = :$PORT" | grep -q LISTEN; then
  fail "port $PORT is already used by another program: $(ss -ltnp "sport = :$PORT" | tail -n +2)"
fi
echo "checks OK"

step "2/7 WebDAV server files in $DIR"
mkdir -p "$DIR/data/zotero"
if [ -s "$CREDS" ]; then
  DAV_PASS=$(sed -n 's/^Password: *//p' "$CREDS")
  echo "keeping the existing password"
else
  DAV_PASS=$(python3 -c 'import secrets; print(secrets.token_urlsafe(24))')
fi
[ -n "$DAV_PASS" ] || fail "couldn't read the password from $CREDS"
docker pull -q "$IMAGE" >/dev/null 2>&1 || docker image inspect "$IMAGE" >/dev/null 2>&1 \
  || fail "couldn't download $IMAGE (Docker Hub may be busy - wait a few minutes and run this again)"
HASH=$(docker run --rm "$IMAGE" bcrypt "$DAV_PASS" | tail -n 1 | tr -d '\r')
case "$HASH" in \$2*) ;; *) fail "couldn't create the password hash (got: $HASH)" ;; esac

cat > "$DIR/config.yml" <<EOF
# Zotero WebDAV server (written by zotero-webdav-setup.sh - edits are overwritten).
address: 0.0.0.0
port: 6065
prefix: /dav
behindProxy: true
directory: /data
permissions: CRUD
log:
  format: console
  colors: false
users:
  - username: $DAV_USER
    password: "{bcrypt}$HASH"
EOF
cat > "$DIR/compose.yaml" <<EOF
# Zotero WebDAV server (written by zotero-webdav-setup.sh).
services:
  webdav:
    image: $IMAGE
    container_name: $CONTAINER
    restart: unless-stopped
    user: "$RUN_AS"
    read_only: true
    security_opt:
      - no-new-privileges:true
    command: ["-c", "/config.yml"]
    ports:
      - "127.0.0.1:$PORT:6065"        # only reachable through nginx (never open in a firewall)
    volumes:
      - ./config.yml:/config.yml:ro
      - ./data:/data
    logging:
      driver: json-file
      options:
        max-size: "1m"
        max-file: "3"
EOF
umask 077
cat > "$CREDS" <<EOF
Zotero WebDAV - enter in Zotero > Settings > Sync > File Syncing
URL: $HOST/dav   (with https)
Username: $DAV_USER
Password: $DAV_PASS
EOF
umask 022
chown -R "$RUN_AS" "$DIR/data"
chown "root:${RUN_AS#*:}" "$DIR/config.yml"
chmod 640 "$DIR/config.yml"
chmod 600 "$CREDS"
echo "files written"

step "3/7 Start the WebDAV server"
cd "$DIR"
docker compose up -d --force-recreate
OK=""
for i in $(seq 1 15); do
  CODE=$(curl -s -o /dev/null -w "%{http_code}" -u "$DAV_USER:$DAV_PASS" -X PROPFIND -H "Depth: 0" "http://127.0.0.1:$PORT/dav/zotero/" || true)
  [ "$CODE" = 207 ] && { OK=1; break; }
  sleep 1
done
[ -n "$OK" ] || { docker logs --tail 20 "$CONTAINER" || true; fail "the WebDAV server isn't answering on 127.0.0.1:$PORT (got $CODE)"; }
CODE=$(curl -s -o /dev/null -w "%{http_code}" -X PROPFIND "http://127.0.0.1:$PORT/dav/zotero/" || true)
[ "$CODE" = 401 ] || fail "the WebDAV server isn't asking for a password (got $CODE)"
echo "WebDAV server running and password-protected"

step "4/7 nginx site for $HOST"
cat > "$SNIPPET" <<'EOF'
# Zotero file sync (WebDAV). The Zotero app can't use the website sign-in,
# so the members gate is off here and the WebDAV server asks for its own
# username/password instead. Installed by zotero-webdav-setup.sh.
location = /dav { return 301 /dav/; }
location /dav/ {
    auth_request off;
    proxy_pass http://127.0.0.1:8090;
    proxy_http_version 1.1;
    proxy_set_header Host $host;
    proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
    proxy_set_header X-Forwarded-Proto $scheme;
    # MOVE/COPY: pass only the path of the Destination header.
    set $zo_dest $http_destination;
    if ($http_destination ~ "^https?://[^/]+(?<zo_path>/.*)$") { set $zo_dest $zo_path; }
    proxy_set_header Destination $zo_dest;
    proxy_redirect off;
    proxy_buffering off;
    proxy_request_buffering off;
    client_max_body_size 1g;
    proxy_read_timeout 600s;
    proxy_send_timeout 600s;
}
EOF
NEW_SITE=""
if [ ! -e "$SITE" ]; then
  NEW_SITE=1
  cat > "$SITE" <<EOF
server {
    listen 80;
    server_name $HOST;
    root $WEBROOT;
    index index.html;

    include snippets/fc-admin-gate.conf;      # members only (landing page)
    include snippets/fc-zotero-dav.conf;      # Zotero WebDAV at /dav/ (own password)

    location / { try_files \$uri \$uri/ =404; }
}
EOF
  echo "site file created"
else
  grep -q "fc-zotero-dav.conf" "$SITE" || fail "$SITE exists but doesn't include fc-zotero-dav.conf - send this to Claude"
  echo "site file already there"
fi
ln -sf "$SITE" /etc/nginx/sites-enabled/
mkdir -p "$WEBROOT/assets"
if ! nginx -t; then
  rm -f "/etc/nginx/sites-enabled/$HOST" "$SNIPPET"
  [ -n "$NEW_SITE" ] && rm -f "$SITE"
  nginx -t && systemctl reload nginx || true
  fail "nginx check failed - the zo. config was removed again, the other sites are untouched"
fi
systemctl reload nginx
echo "nginx reloaded"

step "5/7 HTTPS certificate"
if grep -q "listen.*443" "$SITE"; then
  echo "already has HTTPS"
else
  certbot --nginx -d "$HOST" --redirect --keep-until-expiring \
    || fail "certbot couldn't get a certificate (check the 'zo' DNS record), then run this again"
  grep -q "listen.*443" "$SITE" || fail "certbot finished but $SITE has no HTTPS block"
fi

step "6/7 Landing page"
curl -fsSL "$BASE/subdomains/zo/index.html"    -o "$WEBROOT/index.html"
curl -fsSL "$BASE/subdomains/shared/landing.css" -o "$WEBROOT/assets/landing.css"
chown -R deployuser:www-data "$WEBROOT"
find "$WEBROOT" -type d -exec chmod 755 {} \;
find "$WEBROOT" -type f -exec chmod 644 {} \;
echo "landing page deployed to $WEBROOT"

sleep 1
CODE=$(curl -s -o /dev/null -w "%{http_code}" -u "$DAV_USER:$DAV_PASS" -X PROPFIND -H "Depth: 0" "$DAV_URL/zotero/" || true)
[ "$CODE" = 207 ] || fail "$DAV_URL/zotero/ answered $CODE instead of 207"
CODE=$(curl -s -o /dev/null -w "%{http_code}" -X PROPFIND "$DAV_URL/zotero/" || true)
[ "$CODE" = 401 ] || fail "$DAV_URL isn't asking for a password (got $CODE)"
CODE=$(curl -s -o /dev/null -w "%{http_code}" "https://$HOST/" || true)
[ "$CODE" = 302 ] || fail "the landing page isn't behind the members login (got $CODE)"
echo "https://$HOST works: landing page is members-only, /dav/ is password-protected"

step "7/7 Nightly backup"
cat > /usr/local/bin/zotero-backup.sh <<'EOF'
#!/usr/bin/env bash
# Nightly Zotero files backup (installed by zotero-webdav-setup.sh).
# One folder per day in /root/backups/zotero. Unchanged files are shared
# between days (hard links), so 30 days take little more space than one.
set -euo pipefail
SRC=/opt/zotero-webdav/data/
DEST=/root/backups/zotero
D=$(date +%F)
mkdir -p "$DEST"
chmod 700 "$DEST"
LAST=$(ls -1d "$DEST"/20??-??-?? 2>/dev/null | grep -v "/$D\$" | tail -n 1 || true)
rsync -a --delete ${LAST:+--link-dest="$LAST"} "$SRC" "$DEST/$D/"
# Keep the newest 30 days.
ls -1d "$DEST"/20??-??-?? | head -n -30 | xargs -r rm -rf
echo "$(date '+%F %T') backup OK ($(du -sh "$DEST" | cut -f1) in $DEST)"
EOF
chmod 700 /usr/local/bin/zotero-backup.sh
echo '30 3 * * * root /usr/local/bin/zotero-backup.sh >> /var/log/zotero-backup.log 2>&1' > /etc/cron.d/zotero-backup
chmod 644 /etc/cron.d/zotero-backup
/usr/local/bin/zotero-backup.sh || echo "(first backup run had a problem - see above)"
echo "nightly backup scheduled for 03:30 (kept 30 days in /root/backups/zotero)"

echo
echo "================================================================"
echo " ALL DONE. In Zotero: Settings > Sync > File Syncing >"
echo " 'Sync attachment files in My Library using' WebDAV, then:"
echo
sed -n '2,$p' "$CREDS" | sed 's/^/   /'
echo
echo " Then press 'Verify Server'. Show these again any time with:"
echo "   cat $CREDS"
echo "================================================================"
