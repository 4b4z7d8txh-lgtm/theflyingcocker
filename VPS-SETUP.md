# VPS runbook — The Flying Cocker

How the live site is hosted, how its parts fit together, and how to deploy
changes. Everything below was confirmed on the server on 2026-11-05 unless
marked *(unconfirmed)*.

> Plain-language summary: the website lives on a Linux server (a Fasthosts VPS).
> Nginx serves three addresses: the main site (`www.`), the notes vault (`ob.`)
> and workflows (`wf.`). One login on `www.` gets you into all three.

---

## The server at a glance

| Thing | Value |
|-------|-------|
| Host | Fasthosts VPS, Ubuntu 24.04 LTS |
| Web server | Nginx 1.24 |
| HTTPS | Certbot / Let's Encrypt (auto-renews) |
| Log in | SSH as `root` |
| Files owned by | user `deployuser`, group `www-data` |
| Owner's terminal | **Phone.** Pasted text loses its line breaks, so every command given to the owner must be a **single line** (join steps with `;` or `&&`). |

## Subdomains

| Address | Nginx file | Static pages | `/app/` goes to | Other |
|---|---|---|---|---|
| `theflyingcocker.co.uk`, `www.` | `/etc/nginx/sites-enabled/default` | `/var/www/html` | — | `/auth/` → fc-auth (port 8787), via `snippets/fc-auth-endpoints.conf` |
| `ob.theflyingcocker.co.uk` | `/etc/nginx/sites-enabled/ob.theflyingcocker.co.uk` | `/var/www/ob` | Obsidian in Docker, `127.0.0.1:3000` | `/couchdb/` → CouchDB in Docker, `127.0.0.1:5984` |
| `wf.theflyingcocker.co.uk` | `/etc/nginx/sites-enabled/wf.theflyingcocker.co.uk` | `/var/www/wf` | n8n in Docker, `127.0.0.1:5678` | `/app/webhook/` and `/app/webhook-test/` have their own rule *(probably open to outside callers, for n8n webhooks — unconfirmed)* |

Other nginx snippets: `/etc/nginx/snippets/fc-admin-gate.conf` *(contents not yet read)*.

## Single sign-on (how one login covers every subdomain)

1. The visitor logs in on `www.` (`index.html`) with Firebase email/password.
2. `index.html` sends the Firebase ID token to `POST /auth/session`. The
   **fc-auth** service turns it into an `fc_session` cookie that is valid on
   every `*.theflyingcocker.co.uk` address.
3. On `ob.` and `wf.`, nginx checks each request with
   `auth_request` → `location = /_auth` → `http://127.0.0.1:8787/auth/verify`
   (204 = signed in, 401 = not).
4. If not signed in, `location @fc_login` redirects to
   `https://www.theflyingcocker.co.uk/?next=https://<host><path>`.
   `index.html` sends the visitor back to `next` after login. It only accepts
   `https://*.theflyingcocker.co.uk` addresses.
5. Sign out on `members.html` calls `POST /auth/logout` (clears the cookie) and
   signs out of Firebase.

**fc-auth service**
- Code: `/opt/fc-auth/server.js` (Node, listens on `127.0.0.1:8787` only).
- Unit file: `/opt/fc-auth/fc-auth.service` (systemd service name is probably `fc-auth`).
- Endpoints: `POST /auth/session` (body `{"idToken": "..."}`),
  `POST /auth/logout`, `GET /auth/verify`.
- POSTs are refused (403) unless the `Origin` header is the allowed origin, which
  is the `www.` site. **Log in at `https://www.theflyingcocker.co.uk`, not the
  address without `www`.**
- `/opt/fc-auth/service-account.json` is a Firebase **secret key**. Never print
  it, copy it or commit it.

## Firebase

- Project id: `theflyingcocker`. Sign-in: Email/Password. Public sign-up is off.
  Members are added in Firebase console → Authentication → Users.
- Members-page content: Firestore `members/home`, fields `heading`, `body`.
- `firestore.rules`: `members` readable only when signed in. No writes allowed.

---

## Which files are in GitHub (and which are NOT)

Repo `4b4z7d8txh-lgtm/theflyingcocker`, branch `claude/landing-page-login-rghgnd`.

| On the server | In GitHub? |
|---|---|
| `/var/www/html/index.html` (login) | Yes |
| `/var/www/html/members.html` (menu: Vault, Workflows, Minecraps) | Yes |
| `/var/www/html/assets/firebase-config.js`, `assets/img/portrait.jpg` | Yes |
| `/var/www/html/minecraps.html` | **No — server only** |
| `/var/www/html/index.html.mockup.bak` (old mockup) | No |
| `/var/www/ob/index.html` + `assets/` (vault landing page, has "Open vault" link to `/app/`) | **No — server only** |
| `/var/www/wf/index.html` + `assets/` (workflows landing page) | **No — server only** |
| `/opt/fc-auth/*`, nginx config | **No — server only** |

**Rule: before deploying a file from GitHub, make sure the server's copy
isn't newer or different.** On 2026-11-05, a deploy overwrote server-only
versions of `index.html` and `members.html`. That broke the single sign-on and
removed the menu links until both were rebuilt. Bring any server-only page into
the repo before changing it.

---

## Deploying changes

Pushing to GitHub does **not** update the live site. Run this on the server as
`root` (single line; edit the file list):

```bash
cd /var/www/html && for f in index.html members.html; do curl -fsSL "https://raw.githubusercontent.com/4b4z7d8txh-lgtm/theflyingcocker/claude/landing-page-login-rghgnd/$f" -o "$f" && echo "updated $f" || echo "FAILED $f"; done; chown deployuser:www-data index.html members.html; chmod 644 index.html members.html; echo Done
```

Then test in a **private/incognito tab** (phones cache pages heavily).

---

## Open items

1. **Remove the "Flying Cocker" name and portrait** from `/var/www/ob/index.html`
   and `/var/www/wf/index.html` (owner wants it gone from every page). Bring both
   pages into the repo first.
2. **Double login on the vault:** after the SSO login, the Obsidian container
   asks for its own password *(probably the container's built-in login —
   unconfirmed)*. The owner wants a single login.
3. **Vault opens on Obsidian's Quick Start, not the owner's notes.** CouchDB on
   `ob.` suggests the phone syncs with the **Self-hosted LiveSync** plugin
   *(unconfirmed — ask the owner)*. Fix: in the Obsidian at `ob./app/`, install
   Self-hosted LiveSync and connect it to the same CouchDB, database and
   passphrase as the phone. The notes then download. Don't edit the Quick Start
   vault before syncing.
4. Security hardening: ufw firewall, key-only SSH, `unattended-upgrades`.
5. Optionally automate deploys (e.g. a deploy key + script instead of manual `curl`).

## Handy read-only checks

```bash
nginx -t; systemctl status nginx --no-pager | head -5
nginx -T 2>/dev/null | grep -E "server_name|location|proxy_pass|root "
ss -ltnp | grep -E ":8787|:3000|:5984|:5678"
docker ps
ls -la /var/www/html /var/www/ob /var/www/wf
tail -n 30 /var/log/nginx/error.log
```
