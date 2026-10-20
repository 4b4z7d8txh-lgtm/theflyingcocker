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

[ "$(id -u)" -eq 0 ] || fail "run this as root"

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
apt-get install -y -q nodejs npm curl python3
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
cp /opt/fc-auth/fc-auth.service /etc/systemd/system/
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
WWW=$(grep -rl "server_name.*www.theflyingcocker" /etc/nginx/sites-enabled/ | head -1 || true)
[ -n "$WWW" ] || fail "could not find the main site's Nginx config"
WWW=$(readlink -f "$WWW")
echo "main site config: $WWW"
cp "$WWW" /root/nginx-www-backup.conf
python3 - "$WWW" <<'EOF' || fail "could not add the /auth/ line - send: cat $WWW"
import sys
p = sys.argv[1]; s = open(p).read()
if 'fc-auth-endpoints' in s:
    print('already connected'); sys.exit()
i = s.find('listen 443')
if i < 0:
    sys.exit('no "listen 443" in ' + p)
j = s.index('\n', i) + 1
open(p, 'w').write(s[:j] + '    include snippets/fc-auth-endpoints.conf;\n' + s[j:])
print('connected')
EOF
if ! nginx -t; then
  cp /root/nginx-www-backup.conf "$WWW"
  fail "Nginx check failed - main site config restored, nothing broken"
fi
systemctl reload nginx

step "6/9 n8n and Obsidian (first download takes a few minutes)"
mkdir -p /opt/n8n /opt/obsidian
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
(cd /opt/n8n && docker compose up -d --quiet-pull) || fail "n8n did not start"
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
chown -R deployuser:www-data /var/www/html /var/www/wf /var/www/ob
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
