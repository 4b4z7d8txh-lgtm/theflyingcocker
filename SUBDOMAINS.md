# Subdomains runbook — `wf.` (n8n) and `ob.` (Obsidian)

Two extra sites on the same Fasthosts VPS as the main website:

| Subdomain | What it is | Landing page | The app itself |
|-----------|------------|--------------|----------------|
| `wf.theflyingcocker.co.uk` | **W**ork**f**lows — n8n automations | `/` | `/app/` (n8n editor) |
| `ob.theflyingcocker.co.uk` | **Ob**sidian vault in the browser | `/` | `/app/` (Obsidian desktop, streamed) |

> Plain-language summary: each subdomain gets a small welcome page (from this
> repo) at its front door. Behind the **Open** button, at `/app/`, Nginx hands the
> visitor over to the real program running in a Docker container on the server.

## Files in this repo

```
subdomains/
  wf/index.html        <- landing page for wf.theflyingcocker.co.uk
  ob/index.html        <- landing page for ob.theflyingcocker.co.uk
  shared/landing.css   <- styling shared by both (same look as the main site)
```

On the server each subdomain has its own web root, laid out like this:

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

## 2. Docker (once)

```bash
apt update && apt install -y docker.io docker-compose-v2
systemctl enable --now docker
```

## 3. n8n (for `wf.`)

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
      - GENERIC_TIMEZONE=Europe/London
      - TZ=Europe/London
    volumes:
      - n8n_data:/home/node/.n8n
volumes:
  n8n_data:
EOF
docker compose up -d
```

The first time you open `https://wf.theflyingcocker.co.uk/app/`, n8n asks you to
create the **owner account** — do this straight away, before anyone else finds it.

## 4. Obsidian in the browser (for `ob.`)

Uses the [linuxserver.io Obsidian image](https://docs.linuxserver.io/images/docker-obsidian/),
which runs the real Obsidian app and streams it to the browser.

```bash
mkdir -p /opt/obsidian && cd /opt/obsidian
cat > compose.yaml <<'EOF'
services:
  obsidian:
    image: lscr.io/linuxserver/obsidian:latest
    restart: unless-stopped
    ports:
      - "127.0.0.1:3000:3000"        # only reachable through Nginx
    environment:
      - PUID=1000
      - PGID=1000
      - TZ=Europe/London
      - SUBFOLDER=/app/
      - CUSTOM_USER=CHANGE_ME          # login for the vault
      - PASSWORD=CHANGE_ME_TOO         # use a long, unique password
    volumes:
      - ./config:/config               # your vault lives in here
    shm_size: "1gb"
    security_opt:
      - seccomp:unconfined
EOF
docker compose up -d
```

Open `https://ob.theflyingcocker.co.uk/app/`, sign in with `CUSTOM_USER` /
`PASSWORD`, and create the vault inside `/config` (e.g. `/config/vault`). It's
then just Markdown files in `/opt/obsidian/config/vault` on the server.

> It needs roughly 1 GB of spare RAM while in use — check with `free -h`.

## 5. Web roots + Nginx

```bash
mkdir -p /var/www/wf /var/www/ob

cat > /etc/nginx/sites-available/wf.theflyingcocker.co.uk <<'EOF'
server {
    listen 80;
    server_name wf.theflyingcocker.co.uk;
    root /var/www/wf;
    index index.html;

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

# HTTPS for both (Certbot edits the files above to add the certificates)
certbot --nginx -d wf.theflyingcocker.co.uk -d ob.theflyingcocker.co.uk
```

## 6. Deploy the landing pages

Same `curl` approach as the main site ([VPS-SETUP.md](VPS-SETUP.md)). Set
`BRANCH` to the branch that holds the latest pages:

```bash
BRANCH="claude/wf-ob-landing-pages-2zcq7f"
BASE="https://raw.githubusercontent.com/4b4z7d8txh-lgtm/theflyingcocker/$BRANCH"

for sub in wf ob; do
  mkdir -p /var/www/$sub/assets/img
  curl -fsSL "$BASE/subdomains/$sub/index.html"      -o /var/www/$sub/index.html
  curl -fsSL "$BASE/subdomains/shared/landing.css"   -o /var/www/$sub/assets/landing.css
  curl -fsSL "$BASE/assets/img/portrait.jpg"         -o /var/www/$sub/assets/img/portrait.jpg
  echo "deployed $sub"
done

chown -R deployuser:www-data /var/www/wf /var/www/ob
find /var/www/wf /var/www/ob -type d -exec chmod 755 {} \;
find /var/www/wf /var/www/ob -type f -exec chmod 644 {} \;
```

---

## Security notes

- The landing pages are public (they contain nothing private). The **apps** at
  `/app/` are protected by their **own** logins — n8n's owner account and
  Obsidian's `CUSTOM_USER`/`PASSWORD`. The Firebase members login does **not**
  cover these subdomains.
- Both containers listen on `127.0.0.1` only, so the sole way in is through
  Nginx over HTTPS. Don't open ports 5678 or 3000 in `ufw`.
- Extra lock (optional): add Nginx basic auth in front of `/app/` with
  `apt install apache2-utils && htpasswd -c /etc/nginx/.htpasswd you`, then
  `auth_basic "Private"; auth_basic_user_file /etc/nginx/.htpasswd;` inside the
  `location /app/` block. Leave it off `wf.`'s webhook URLs if outside services
  need to call them (`/app/webhook/`).

## Backups

```bash
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
