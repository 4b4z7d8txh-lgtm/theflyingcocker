#!/usr/bin/env bash
# -------------------------------------------------------------------------
# One-shot server setup for wf. (n8n) and ob. (Obsidian) + single sign-on
# -------------------------------------------------------------------------
# Does everything in SUBDOMAINS.md in one go, so it can be started with a
# single pasted line (handy from a phone SSH app):
#
#   curl -fsSL https://raw.githubusercontent.com/4b4z7d8txh-lgtm/theflyingcocker/claude/wf-ob-landing-pages-2zcq7f/server-setup.sh -o /root/fc-setup.sh && bash /root/fc-setup.sh
#
# Safe to run again: finished steps are skipped or simply refreshed.
# Run as root on the VPS.
# -------------------------------------------------------------------------

set -euo pipefail

BRANCH="claude/wf-ob-landing-pages-2zcq7f"
BASE="https://raw.githubusercontent.com/4b4z7d8txh-lgtm/theflyingcocker/$BRANCH"
KEY=/opt/fc-auth/service-account.json
export DEBIAN_FRONTEND=noninteractive

step() { echo; echo "=== $* ==="; }
fail() { echo; echo "STOPPED: $*"; echo "Send this output to Claude."; exit 1; }
fetch() { curl -fsSL --retry 3 "$BASE/$1" -o "$2" || fail "could not download $1"; }

# Any unexpected failure also ends with a clear STOPPED message.
trap 'fail "the command on line $LINENO of the script failed (see the lines above)"' ERR

[ "$(id -u)" -eq 0 ] || fail "run this as root"

echo "fc-setup version: 2026-10-23 (node fix)"

step "1/9 Room check"
free -h | sed -n '1,2p'
df -h / | tail -1

step "2/9 Firebase key"
mkdir -p /opt/fc-auth
if [ ! -s "$KEY" ] && [ -s /root/service-account.json ]; then
  mv /root/service-account.json "$KEY"
fi
if [ ! -s "$KEY" ]; then
  echo "Paste the WHOLE contents of the Firebase key (.json) file, then press Enter:"
  IFS= read -r KEYTEXT
  printf '%s\n' "$KEYTEXT" > "$KEY"
fi
python3 - "$KEY" <<'EOF' || { rm -f "$KEY"; fail "that key isn't valid - run the script again and paste the full key"; }
import json, sys
k = json.load(open(sys.argv[1]))
assert k.get("type") == "service_account" and k.get("project_id") == "theflyingcocker"
print("key OK for project", k["project_id"])
EOF

step "3/9 Packages (Node.js, Docker)"
apt-get update -q
apt-get install -y -q curl python3
# Node.js may already be installed (e.g. from NodeSource, whose nodejs
# includes npm and conflicts with Ubuntu's npm package), so only add what's missing.
command -v node >/dev/null 2>&1 || apt-get install -y -q nodejs
command -v npm  >/dev/null 2>&1 || apt-get install -y -q npm
NODE=$(command -v node)
echo "using $NODE $(node --version), npm $(npm --version)"
if ! command -v docker >/dev/null 2>&1; then
  apt-get install -y -q docker.io docker-compose-v2
fi
docker compose version >/dev/null 2>&1 || apt-get install -y -q docker-compose-v2
systemctl enable --now docker

step "4/9 Sign-in helper"
id fcauth >/dev/null 2>&1 || useradd --system --no-create-home --shell /usr/sbin/nologin fcauth
cd /opt/fc-auth
for f in server.js package.json fc-auth.service; do fetch "auth-service/$f" "$f"; done
npm install --omit=dev --no-audit --no-fund --loglevel=error
chown -R root:fcauth /opt/fc-auth
chmod 640 "$KEY"
sed "s#^ExecStart=.*#ExecStart=$NODE server.js#" /opt/fc-auth/fc-auth.service > /etc/systemd/system/fc-auth.service
systemctl daemon-reload
systemctl enable fc-auth >/dev/null 2>&1
systemctl restart fc-auth
CODE=000
for _ in 1 2 3 4 5 6 7 8 9 10; do
  sleep 1
  CODE=$(curl -s -o /dev/null -w "%{http_code}" http://127.0.0.1:8787/auth/verify || true)
  [ "$CODE" = "401" ] && break
done
[ "$CODE" = "401" ] || { journalctl -u fc-auth -n 20 --no-pager; fail "sign-in helper did not start"; }
echo "helper running"

step "5/9 Nginx: connect the main site to the helper"
cat > /etc/nginx/snippets/fc-auth-endpoints.conf <<'EOF'
location /auth/ {
    proxy_pass http://127.0.0.1:8787;
    proxy_set_header Host $host;
    proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
}
EOF
cat > /etc/nginx/snippets/fc-admin-gate.conf <<'EOF'
auth_request /_auth;
error_page 401 = @fc_login;

location = /_auth {
    internal;
    auth_request off;
    proxy_pass http://127.0.0.1:8787/auth/verify;
    proxy_pass_request_body off;
    proxy_set_header Content-Length "";
    proxy_set_header Cookie $http_cookie;
}
location @fc_login { return 302 https://www.theflyingcocker.co.uk/?next=https://$host$uri; }
EOF
# -R (not -r) so the search follows the symlinks in sites-enabled.
WWW=$(grep -Rl "server_name.*theflyingcocker" /etc/nginx/sites-enabled/ /etc/nginx/conf.d/ 2>/dev/null | head -1 || true)
[ -n "$WWW" ] || fail "could not find the main site's Nginx config"
WWW=$(readlink -f "$WWW")
echo "main site config: $WWW"
cp "$WWW" /root/nginx-www-backup.conf
python3 - "$WWW" <<'EOF' || fail "could not add the /auth/ line - send: cat $WWW"
# Add the include inside the HTTPS server block for theflyingcocker.co.uk,
# ignoring commented-out lines (the stock "default" file has several).
import re, sys
p = sys.argv[1]; lines = open(p).read().split('\n')
if any('fc-auth-endpoints' in l and not l.strip().startswith('#') for l in lines):
    print('already connected'); sys.exit()
depth, block, target = 0, None, None
for n, l in enumerate(lines):
    code = l.split('#', 1)[0]
    if depth == 0 and re.match(r'\s*server\s*\{', code):
        block = {'listen': None, 'ours': False}
    if block is not None:
        if block['listen'] is None and re.match(r'\s*listen\s+(\[::\]:)?443\b', code):
            block['listen'] = n
        if re.search(r'server_name\s[^;]*theflyingcocker', code):
            block['ours'] = True
    depth += code.count('{') - code.count('}')
    if depth == 0 and block is not None:
        if block['ours'] and block['listen'] is not None:
            target = block['listen']; break
        block = None
if target is None:
    sys.exit('no HTTPS server block for theflyingcocker.co.uk in ' + p)
lines.insert(target + 1, '    include snippets/fc-auth-endpoints.conf;')
open(p, 'w').write('\n'.join(lines))
print('connected')
EOF
if ! nginx -t; then
  cp /root/nginx-www-backup.conf "$WWW"
  fail "Nginx check failed - main site config restored, nothing broken"
fi
systemctl reload nginx

step "6/9 n8n and Obsidian (first download takes a few minutes)"
# --- n8n: reuse the one already on the server if there is one -------------
N8N_DIR=$(docker inspect -f '{{index .Config.Labels "com.docker.compose.project.working_dir"}}' n8n-n8n-1 2>/dev/null || true)
if [ -n "$N8N_DIR" ]; then
  echo "using the existing n8n in $N8N_DIR (workflows kept)"
  cd "$N8N_DIR"
  if [ -e docker-compose.yml ] || [ -e docker-compose.yaml ]; then OVR=docker-compose.override.yml; else OVR=compose.override.yaml; fi
  if [ -e "$OVR" ] && ! grep -q "theflyingcocker setup" "$OVR"; then
    fail "$N8N_DIR/$OVR already exists - not touching it"
  fi
  # Serve n8n under wf.../app/ behind Nginx; Caddy isn't needed (Nginx
  # already owns ports 80/443), so keep it switched off.
  cat > "$OVR" <<'EOF'
# Added by theflyingcocker setup: n8n behind Nginx at https://wf.theflyingcocker.co.uk/app/
services:
  n8n:
    environment:
      - N8N_PATH=/app/
      - WEBHOOK_URL=https://wf.theflyingcocker.co.uk/app/
      - N8N_PROXY_HOPS=1
      - N8N_USER_MANAGEMENT_JWT_DURATION_HOURS=8760
  caddy:
    profiles: ["disabled"]
EOF
  docker compose config -q || fail "the n8n settings didn't validate"
  docker compose up -d n8n || fail "n8n did not restart"
else
  mkdir -p /opt/n8n
  cat > /opt/n8n/compose.yaml <<'EOF'
services:
  n8n:
    image: docker.n8n.io/n8nio/n8n:latest
    restart: unless-stopped
    ports:
      - "127.0.0.1:5678:5678"
    environment:
      - N8N_HOST=wf.theflyingcocker.co.uk
      - N8N_PROTOCOL=https
      - N8N_PATH=/app/
      - WEBHOOK_URL=https://wf.theflyingcocker.co.uk/app/
      - N8N_PROXY_HOPS=1
      - N8N_USER_MANAGEMENT_JWT_DURATION_HOURS=8760
      - GENERIC_TIMEZONE=Europe/London
      - TZ=Europe/London
    volumes:
      - n8n_data:/home/node/.n8n
volumes:
  n8n_data:
EOF
  (cd /opt/n8n && docker compose up -d --quiet-pull) || fail "n8n did not start"
fi

# --- Obsidian in the browser ----------------------------------------------
mkdir -p /opt/obsidian
if [ ! -e /opt/obsidian/compose.yaml ] && ss -tln | grep -q '127.0.0.1:3000 \|:3000 '; then
  fail "port 3000 is already used by another program"
fi
cat > /opt/obsidian/compose.yaml <<'EOF'
services:
  obsidian:
    image: lscr.io/linuxserver/obsidian:latest
    restart: unless-stopped
    ports:
      - "127.0.0.1:3000:3000"
    environment:
      - PUID=1000
      - PGID=1000
      - TZ=Europe/London
      - SUBFOLDER=/app/
    volumes:
      - ./config:/config
    shm_size: "1gb"
    security_opt:
      - seccomp:unconfined
EOF
# If the Obsidian LiveSync CouchDB is running, put the browser Obsidian on its
# network so LiveSync can reach it at http://couchdb-for-obsidian:5984
COUCH_NET=$(docker inspect -f '{{range $k, $v := .NetworkSettings.Networks}}{{$k}} {{end}}' couchdb-for-obsidian 2>/dev/null | awk '{print $1}' || true)
if [ -n "$COUCH_NET" ]; then
  cat >> /opt/obsidian/compose.yaml <<EOF
    networks:
      - default
      - couchdb
networks:
  couchdb:
    name: $COUCH_NET
    external: true
EOF
  echo "Obsidian will be able to reach CouchDB at http://couchdb-for-obsidian:5984"
fi
(cd /opt/obsidian && docker compose up -d --quiet-pull) || fail "Obsidian did not start"

step "7/9 Nginx: wf. and ob. sites"
mkdir -p /var/www/wf /var/www/ob
# Only written the first time: Certbot later adds HTTPS to these files.
if [ ! -e /etc/nginx/sites-available/wf.theflyingcocker.co.uk ]; then
cat > /etc/nginx/sites-available/wf.theflyingcocker.co.uk <<'EOF'
server {
    listen 80;
    server_name wf.theflyingcocker.co.uk;
    root /var/www/wf;
    index index.html;

    include snippets/fc-admin-gate.conf;

    location ~ ^/app/(webhook|webhook-test)/ {
        auth_request off;
        rewrite ^/app/(.*)$ /$1 break;
        proxy_pass http://127.0.0.1:5678;
        proxy_set_header Host $host;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
        client_max_body_size 50m;
    }

    location = /app { return 301 /app/; }
    location /app/ {
        proxy_pass http://127.0.0.1:5678/;
        proxy_http_version 1.1;
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection "upgrade";
        proxy_set_header Host $host;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
        proxy_buffering off;
        proxy_read_timeout 3600s;
        client_max_body_size 50m;
    }
    location / { try_files $uri $uri/ =404; }
}
EOF
fi
if [ ! -e /etc/nginx/sites-available/ob.theflyingcocker.co.uk ]; then
cat > /etc/nginx/sites-available/ob.theflyingcocker.co.uk <<'EOF'
server {
    listen 80;
    server_name ob.theflyingcocker.co.uk;
    root /var/www/ob;
    index index.html;

    include snippets/fc-admin-gate.conf;

    location = /app { return 301 /app/; }
    location /app/ {
        proxy_pass http://127.0.0.1:3000;
        proxy_http_version 1.1;
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection "upgrade";
        proxy_set_header Host $host;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
        proxy_buffering off;
        proxy_read_timeout 86400s;
        client_max_body_size 100m;
    }
    location / { try_files $uri $uri/ =404; }
}
EOF
fi
ln -sf /etc/nginx/sites-available/wf.theflyingcocker.co.uk /etc/nginx/sites-enabled/
ln -sf /etc/nginx/sites-available/ob.theflyingcocker.co.uk /etc/nginx/sites-enabled/
nginx -t || fail "Nginx check failed for the wf./ob. sites"
systemctl reload nginx

step "8/9 Website pages"
cd /var/www/html
for f in index.html members.html minecraps.html assets/members-guard.js assets/session.js \
         assets/members.css assets/firebase-config.js assets/img/portrait.jpg; do
  mkdir -p "$(dirname "$f")"; fetch "$f" "$f"; echo "updated $f"
done
for sub in wf ob; do
  mkdir -p /var/www/$sub/assets/img
  fetch "subdomains/$sub/index.html"    /var/www/$sub/index.html
  fetch "subdomains/shared/landing.css" /var/www/$sub/assets/landing.css
  fetch "assets/img/portrait.jpg"       /var/www/$sub/assets/img/portrait.jpg
  echo "deployed $sub"
done
OWNER=deployuser; id deployuser >/dev/null 2>&1 || OWNER=root
chown -R "$OWNER":www-data /var/www/html /var/www/wf /var/www/ob
find /var/www/html /var/www/wf /var/www/ob -type d -exec chmod 755 {} \;
find /var/www/html /var/www/wf /var/www/ob -type f -exec chmod 644 {} \;

step "9/9 HTTPS for wf. and ob."
MYIP=$(curl -4 -s --max-time 10 ifconfig.me || true)
DNS_OK=yes
for h in wf.theflyingcocker.co.uk ob.theflyingcocker.co.uk; do
  IP=$(getent ahostsv4 "$h" | awk 'NR==1{print $1}')
  echo "$h -> ${IP:-not found yet} (this server: $MYIP)"
  [ -n "$IP" ] && [ "$IP" = "$MYIP" ] || DNS_OK=no
done
if [ "$DNS_OK" = yes ]; then
  certbot --nginx --redirect -n --agree-tos --register-unsafely-without-email \
    -d wf.theflyingcocker.co.uk -d ob.theflyingcocker.co.uk || fail "Certbot could not get the certificate"
  HTTPS_DONE=yes
else
  HTTPS_DONE=no
fi

echo
echo "================================================================"
echo " ALL DONE."
if [ "$HTTPS_DONE" = no ]; then
  echo
  echo " Only HTTPS is left: the wf/ob DNS records aren't visible yet."
  echo " Wait 10-30 minutes, then paste this same line again:"
  echo "   bash /root/fc-setup.sh"
fi
echo
echo " Test in a private window: sign in on www.theflyingcocker.co.uk,"
echo " then open Workflows and Vault from the menu."
echo "================================================================"
