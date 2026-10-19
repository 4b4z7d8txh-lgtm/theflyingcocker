# Subdomains runbook — `wf.` (n8n) and `ob.` (Obsidian)

Two extra sites on the same Fasthosts VPS as the main website:

| Subdomain | What it is | Landing page | The app itself |
|-----------|------------|--------------|----------------|
| `wf.theflyingcocker.co.uk` | **W**ork**f**lows — n8n automations | `/` | `/app/` (n8n editor) |
| `ob.theflyingcocker.co.uk` | **Ob**sidian vault in the browser | `/` | `/app/` (Obsidian desktop, streamed) |

> Plain-language summary: each subdomain gets a small welcome page (from this
> repo) at its front door. Behind the **Open** button, at `/app/`, Nginx hands the
> visitor over to the real program running in a Docker container on the server.
> **Both subdomains are admin-only**, and the admin gets in with the normal
> Flying Cocker sign-in — no second password.

## Who can see what

| | Admin (you) | Other members | Not signed in |
|---|---|---|---|
| `www` login page | ✓ | ✓ | ✓ |
| Members home (`members.html`) | ✓ | → sent to Minecraps | → login |
| Minecraps (`minecraps.html`) | ✓ | ✓ | → login |
| `wf.` and `ob.` (everything on them) | ✓ | → sent to Minecraps | → login, then back |

## How the single sign-on works

1. You sign in on `www.theflyingcocker.co.uk` as usual (Firebase).
2. Because your account carries the **admin** flag, the page hands your login to a
   tiny helper program on the VPS (`auth-service/`). It checks it with Firebase
   and sets one secure cookie, `fc_session`, for **all** `*.theflyingcocker.co.uk`.
3. Whenever anyone opens `wf.` or `ob.`, Nginx first asks the helper about that
   cookie (`auth_request`). Admin → in. Signed-in member → sent to Minecraps.
   No cookie → sent to the login page, then straight back to where they were going.

Like the website login, it ends when the browser is closed (and after 5 days at
most). **Sign out** on the members pages clears it everywhere.

## Files in this repo

```
subdomains/
  wf/index.html        <- landing page for wf.theflyingcocker.co.uk
  ob/index.html        <- landing page for ob.theflyingcocker.co.uk
  shared/landing.css   <- styling shared by both (same look as the main site)
auth-service/
  server.js            <- the single sign-on helper (Node, 127.0.0.1:8787)
  set-admin.js         <- marks a Firebase account as admin
  package.json
  fc-auth.service      <- systemd unit to keep it running
assets/session.js      <- browser side: admin check + hands the login to the helper
```

On the server each subdomain has its own web root:

```
/var/www/wf/  (and the same for /var/www/ob/)
  index.html
  assets/landing.css
  assets/img/portrait.jpg
```

The **Open** buttons link to `/app/`. If you ever serve the app somewhere else,
change the `href="/app/"` line (marked `APP_URL`) in that page's `index.html`.

Run everything below **on the VPS as `root`** unless a step says otherwise.

---

## 1. DNS

Add two **A records** where the domain's DNS is managed (same place as `www` and `mc`):

| Type | Name | Value            | TTL  |
|------|------|------------------|------|
| A    | `wf` | `YOUR_SERVER_IP` | 3600 |
| A    | `ob` | `YOUR_SERVER_IP` | 3600 |

Check: `dig +short wf.theflyingcocker.co.uk` and `dig +short ob.theflyingcocker.co.uk`.

## 2. The single sign-on helper

**a. Get a Firebase service-account key** (lets the helper check logins):
Firebase console → ⚙ **Project settings → Service accounts → Generate new
private key**. It downloads a `.json` file. Treat it like a password — never
commit it to GitHub.

**b. Install it on the VPS:**

```bash
apt update && apt install -y nodejs npm
useradd --system --no-create-home --shell /usr/sbin/nologin fcauth

BRANCH="claude/wf-ob-landing-pages-2zcq7f"
BASE="https://raw.githubusercontent.com/4b4z7d8txh-lgtm/theflyingcocker/$BRANCH"
mkdir -p /opt/fc-auth && cd /opt/fc-auth
for f in server.js set-admin.js package.json fc-auth.service; do
  curl -fsSL "$BASE/auth-service/$f" -o "$f"
done
npm install --omit=dev
```

Copy the key file onto the server as `/opt/fc-auth/service-account.json`
(e.g. from your computer: `scp ~/Downloads/theflyingcocker-*.json root@YOUR_SERVER_IP:/opt/fc-auth/service-account.json`), then:

```bash
chown -R root:fcauth /opt/fc-auth
chmod 640 /opt/fc-auth/service-account.json

cp /opt/fc-auth/fc-auth.service /etc/systemd/system/
systemctl daemon-reload && systemctl enable --now fc-auth
systemctl status fc-auth --no-pager      # should say "active (running)"
```

**c. Make yourself the admin** (use the email you log in with):

```bash
cd /opt/fc-auth
GOOGLE_APPLICATION_CREDENTIALS=/opt/fc-auth/service-account.json node set-admin.js you@example.com
```

Then **sign out and back in** on the website so the admin flag takes effect.
(To remove it from someone: add `--remove` to the end.)

**d. Publish the updated Firestore rules** — the members home content is now
admin-only. Paste `firestore.rules` into Firebase console → Firestore Database →
Rules → **Publish**.

## 3. Nginx snippets (shared)

```bash
# Lets www talk to the helper (sign-in / sign-out)
cat > /etc/nginx/snippets/fc-auth-endpoints.conf <<'EOF'
location /auth/ {
    proxy_pass http://127.0.0.1:8787;
    proxy_set_header Host $host;
    proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
}
EOF

# The admin-only gate, included in each subdomain
cat > /etc/nginx/snippets/fc-admin-gate.conf <<'EOF'
auth_request /_auth;
error_page 401 = @fc_login;
error_page 403 = @fc_denied;

location = /_auth {
    internal;
    auth_request off;
    proxy_pass http://127.0.0.1:8787/auth/verify;
    proxy_pass_request_body off;
    proxy_set_header Content-Length "";
    proxy_set_header Cookie $http_cookie;
}
location @fc_login  { return 302 https://www.theflyingcocker.co.uk/?next=https://$host$uri; }
location @fc_denied { return 302 https://www.theflyingcocker.co.uk/minecraps.html; }
EOF
```

Now add **one line** to the main website's HTTPS server block — the one with
`server_name theflyingcocker.co.uk www.theflyingcocker.co.uk;` and `listen 443`
(find it with `grep -rl "server_name.*www.theflyingcocker" /etc/nginx/sites-enabled/`):

```nginx
    include snippets/fc-auth-endpoints.conf;
```

## 4. Docker (once)

```bash
apt install -y docker.io docker-compose-v2
systemctl enable --now docker
```

## 5. n8n (for `wf.`)

```bash
mkdir -p /opt/n8n && cd /opt/n8n
cat > compose.yaml <<'EOF'
services:
  n8n:
    image: docker.n8n.io/n8nio/n8n:latest
    restart: unless-stopped
    ports:
      - "127.0.0.1:5678:5678"        # only reachable through Nginx
    environment:
      - N8N_HOST=wf.theflyingcocker.co.uk
      - N8N_PROTOCOL=https
      - N8N_PATH=/app/
      - WEBHOOK_URL=https://wf.theflyingcocker.co.uk/app/
      - N8N_PROXY_HOPS=1
      # n8n always keeps its own owner login. Remember it for a year so you
      # only ever type it once per browser.
      - N8N_USER_MANAGEMENT_JWT_DURATION_HOURS=8760
      - GENERIC_TIMEZONE=Europe/London
      - TZ=Europe/London
    volumes:
      - n8n_data:/home/node/.n8n
volumes:
  n8n_data:
EOF
docker compose up -d
```

> **One exception to "no second password":** n8n (the free edition) can't
> switch its own login off. The first time you open `wf.…/app/` it asks you to
> create the owner account; after that, the setting above keeps you signed in
> to n8n for a year on that browser. Nobody but you can even reach that screen,
> because the admin gate sits in front of it.

## 6. Obsidian in the browser (for `ob.`)

Uses the [linuxserver.io Obsidian image](https://docs.linuxserver.io/images/docker-obsidian/),
which runs the real Obsidian app and streams it to the browser. It has **no
password of its own** here — the admin gate is the lock.

```bash
mkdir -p /opt/obsidian && cd /opt/obsidian
cat > compose.yaml <<'EOF'
services:
  obsidian:
    image: lscr.io/linuxserver/obsidian:latest
    restart: unless-stopped
    ports:
      - "127.0.0.1:3000:3000"        # only reachable through Nginx (never open in ufw)
    environment:
      - PUID=1000
      - PGID=1000
      - TZ=Europe/London
      - SUBFOLDER=/app/
    volumes:
      - ./config:/config               # your vault lives in here
    shm_size: "1gb"
    security_opt:
      - seccomp:unconfined
EOF
docker compose up -d
```

Open `https://ob.theflyingcocker.co.uk/app/` and create the vault inside
`/config` (e.g. `/config/vault`). It's then just Markdown files in
`/opt/obsidian/config/vault` on the server.

> It needs roughly 1 GB of spare RAM while in use — check with `free -h`.

## 7. Subdomain sites in Nginx

```bash
mkdir -p /var/www/wf /var/www/ob

cat > /etc/nginx/sites-available/wf.theflyingcocker.co.uk <<'EOF'
server {
    listen 80;
    server_name wf.theflyingcocker.co.uk;
    root /var/www/wf;
    index index.html;

    include snippets/fc-admin-gate.conf;      # admin only

    # Webhooks must stay reachable by outside services (give each webhook
    # its own auth inside n8n if it needs one).
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
        proxy_pass http://127.0.0.1:5678/;        # trailing slash strips /app/
        proxy_http_version 1.1;
        proxy_set_header Upgrade $http_upgrade;   # n8n uses websockets
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

cat > /etc/nginx/sites-available/ob.theflyingcocker.co.uk <<'EOF'
server {
    listen 80;
    server_name ob.theflyingcocker.co.uk;
    root /var/www/ob;
    index index.html;

    include snippets/fc-admin-gate.conf;      # admin only

    location = /app { return 301 /app/; }
    location /app/ {
        proxy_pass http://127.0.0.1:3000;         # no slash: the app expects /app/
        proxy_http_version 1.1;
        proxy_set_header Upgrade $http_upgrade;   # the stream uses websockets
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

ln -s /etc/nginx/sites-available/wf.theflyingcocker.co.uk /etc/nginx/sites-enabled/
ln -s /etc/nginx/sites-available/ob.theflyingcocker.co.uk /etc/nginx/sites-enabled/
nginx -t && systemctl reload nginx

# HTTPS for both (Certbot copies the blocks above into HTTPS versions)
certbot --nginx -d wf.theflyingcocker.co.uk -d ob.theflyingcocker.co.uk
```

## 8. Deploy the pages

Same `curl` approach as the main site ([VPS-SETUP.md](VPS-SETUP.md)).

```bash
BRANCH="claude/wf-ob-landing-pages-2zcq7f"
BASE="https://raw.githubusercontent.com/4b4z7d8txh-lgtm/theflyingcocker/$BRANCH"

# Main site: the login + members pages changed for admin/member roles
cd /var/www/html
for f in index.html members.html minecraps.html assets/members-guard.js assets/session.js; do
  curl -fsSL "$BASE/$f" -o "$f" && echo "updated $f" || echo "FAILED $f"
done

# Subdomain landing pages
for sub in wf ob; do
  mkdir -p /var/www/$sub/assets/img
  curl -fsSL "$BASE/subdomains/$sub/index.html"    -o /var/www/$sub/index.html
  curl -fsSL "$BASE/subdomains/shared/landing.css" -o /var/www/$sub/assets/landing.css
  curl -fsSL "$BASE/assets/img/portrait.jpg"       -o /var/www/$sub/assets/img/portrait.jpg
  echo "deployed $sub"
done

chown -R deployuser:www-data /var/www/html /var/www/wf /var/www/ob
find /var/www/html /var/www/wf /var/www/ob -type d -exec chmod 755 {} \;
find /var/www/html /var/www/wf /var/www/ob -type f -exec chmod 644 {} \;
```

## 9. Test it (use a private/incognito window)

1. Open `https://wf.theflyingcocker.co.uk` → you land on the **login page**.
2. Sign in as yourself → you're sent straight back to the `wf.` landing page.
3. Open `https://ob.theflyingcocker.co.uk` → it opens with **no** login prompt.
4. The members pages now show **Home · Minecraps · Workflows · Vault** for you.
5. In another private window, sign in as a normal member → you land on
   **Minecraps**, see only that tab, and `wf.`/`ob.` bounce you back to Minecraps.

---

## Troubleshooting

```bash
systemctl status fc-auth --no-pager     # is the helper running?
journalctl -u fc-auth -n 50 --no-pager  # its recent log
curl -s -o /dev/null -w "%{http_code}\n" http://127.0.0.1:8787/auth/verify   # expect 401
```

- **Loops back to the login page after signing in:** the `/auth/` line is missing
  from the www HTTPS block (step 3), or the helper isn't running.
- **You're sent to Minecraps instead of in:** the admin flag isn't on your
  account (step 2c), or you haven't signed out and back in since setting it.
- **Members home says "Could not load members content":** publish the new
  Firestore rules (step 2d) and make sure you're the admin.

## Security notes

- The helper and both apps listen on `127.0.0.1` only; the sole way in is
  through Nginx over HTTPS. Don't open ports 8787, 5678 or 3000 in `ufw`.
- The sign-on cookie is `HttpOnly`, `Secure` and only issued to admin accounts.
  Sign-in/out calls are only accepted from `https://www.theflyingcocker.co.uk`.
- To lock someone out immediately, disable them in Firebase console →
  Authentication → Users (the helper honours revoked/disabled accounts within a
  minute).

## Backups

```bash
mkdir -p /root/backups
# n8n workflows + credentials
docker run --rm -v n8n_n8n_data:/d -v /root/backups:/b alpine tar czf /b/n8n-$(date +%F).tgz -C /d .
# Obsidian vault
tar czf /root/backups/obsidian-$(date +%F).tgz -C /opt/obsidian config
```

## Updating the apps

```bash
cd /opt/n8n && docker compose pull && docker compose up -d
cd /opt/obsidian && docker compose pull && docker compose up -d
```
