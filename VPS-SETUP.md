# VPS runbook — The Flying Cocker

How the live site is hosted, how its parts fit together, and how to deploy
changes. Server facts below were confirmed on the server on 2026-11-05 unless
marked *(unconfirmed)*.

> Plain-language summary: the website lives on a Linux server (a Fasthosts VPS).
> Nginx serves three addresses: the main site (`www.`), the notes vault (`ob.`)
> and workflows (`wf.`). One login on `www.` gets you into all three.

Related guides in this repo:
- **[SUBDOMAINS.md](SUBDOMAINS.md)**: how `wf.`/`ob.`, Docker, nginx and the sign-on helper were set up.
- **[OBSIDIAN-SYNC.md](OBSIDIAN-SYNC.md)**: phone + work-laptop sync (Self-hosted LiveSync via CouchDB) and backups.
- **[MINECRAFT-SERVER.md](MINECRAFT-SERVER.md)**: the Bedrock game server (`mc.`).
- **[SETUP.md](SETUP.md)**: Firebase setup.

---

## Source of truth

- **Repo:** `4b4z7d8txh-lgtm/theflyingcocker`, branch **`main`**.
- `main` contains everything from the older `claude/...` branches. Those
  branches are history only: **don't deploy from them.**
- The server downloads files from the public raw GitHub URL with `curl`. No
  keys are needed.

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

| Address | Nginx file | Static pages (repo → server) | `/app/` goes to | Other |
|---|---|---|---|---|
| `theflyingcocker.co.uk`, `www.` | `/etc/nginx/sites-enabled/default` | repo root → `/var/www/html` | — | `/auth/` → sign-on helper on `127.0.0.1:8787` (`/etc/nginx/snippets/fc-auth-endpoints.conf`) |
| `ob.theflyingcocker.co.uk` | `/etc/nginx/sites-enabled/ob.theflyingcocker.co.uk` | `subdomains/ob/` → `/var/www/ob` | Obsidian in Docker, `127.0.0.1:3000` | `/couchdb/` → CouchDB in Docker, `127.0.0.1:5984` (LiveSync) |
| `wf.theflyingcocker.co.uk` | `/etc/nginx/sites-enabled/wf.theflyingcocker.co.uk` | `subdomains/wf/` → `/var/www/wf` | n8n in Docker, `127.0.0.1:5678` | `/app/webhook/` and `/app/webhook-test/` have their own rule (n8n webhooks) |

`subdomains/shared/landing.css` is deployed as `assets/landing.css` in both
`/var/www/ob` and `/var/www/wf`.
Also present: `/etc/nginx/snippets/fc-admin-gate.conf` (the members-only gate).

### What's in `/var/www/html`

```
index.html                 <- login page (Firebase sign-in, then sign-on cookie, then ?next=)
members.html               <- members home: nav (Home, Minecraps, Workflows, Vault) + Firestore content
minecraps.html             <- members page: family Minecraft server info
assets/firebase-config.js  <- Firebase web config (public by design)
assets/session.js          <- single sign-on: /auth/session, /auth/logout, safe ?next=
assets/members-guard.js    <- shared login gate used by every members page
assets/members.css         <- shared members styling
assets/img/portrait.jpg    <- no longer shown on any page
index.html.mockup.bak      <- old mockup (not linked)
```

New members page: copy `minecraps.html`, call `guardMembersPage()`, and add it
to the `<nav>` in every members page.

## Single sign-on (one login for every subdomain)

1. Login on `www.` (`index.html`) with Firebase email/password.
2. `assets/session.js` sends the Firebase ID token to `POST /auth/session`. The
   sign-on helper sets an `fc_session` cookie valid on all `*.theflyingcocker.co.uk`.
3. On `ob.`/`wf.`, nginx checks every request with `auth_request` → `location = /_auth`
   → `http://127.0.0.1:8787/auth/verify` (204 = in, 401 = out).
4. Not signed in → `location @fc_login` → `https://www.theflyingcocker.co.uk/?next=https://<host><path>`.
   After login, `index.html` returns there (only `https://*.theflyingcocker.co.uk`).
5. Sign out calls `POST /auth/logout` and signs out of Firebase.

**Sign-on helper (fc-auth)**
- Source in repo: `auth-service/`. Live copy: `/opt/fc-auth/` (Node, `server.js`,
  listens on `127.0.0.1:8787` only). The systemd unit is `fc-auth.service`.
- POSTs are refused (403) unless `Origin` is the `www.` site. **Log in at
  `https://www.theflyingcocker.co.uk`, not the address without `www`.**
- `/opt/fc-auth/service-account.json` is a Firebase **secret key**. Never print,
  copy or commit it (`.gitignore` blocks `service-account*.json`).

## Firebase

- Project id `theflyingcocker`. Email/Password sign-in, public sign-up off.
  Add members in Firebase console → Authentication → Users.
- Members home content: Firestore `members/home` (`heading`, `body`).
- If login says "unauthorized domain": add the domain in Authentication →
  Settings → Authorized domains.

---

## Deploying changes

Pushing to GitHub does **not** update the live site. Run on the server as
`root`. Each command is a single line, so it can be pasted from a phone.

**Main site** (edit the file list to what changed):
```bash
cd /var/www/html && for f in index.html members.html minecraps.html assets/session.js assets/members-guard.js assets/members.css assets/firebase-config.js; do mkdir -p "$(dirname "$f")"; curl -fsSL "https://raw.githubusercontent.com/4b4z7d8txh-lgtm/theflyingcocker/main/$f" -o "$f" && echo "updated $f" || echo "FAILED $f"; done; chown -R deployuser:www-data /var/www/html; echo Done
```

**Subdomain landing pages** (`ob` or `wf`): see SUBDOMAINS.md §8 for the
exact source → destination paths.

Then test in a **private/incognito tab**, because phones cache pages heavily.

**Rule:** the repo must match the server. If a change is made directly on the
server, put it in the repo too. Otherwise the next deploy silently overwrites it.
This happened on 2026-11-05: a deploy from an out-of-date branch replaced the
live login and members pages and broke the sign-on until they were rebuilt.
After the switch to `main`, run the main-site deploy above once so the
server matches `main` again.

---

## Open items

0. **Finish the switch to `main` (from the 2026-11-05 chat):**
   - On GitHub, make `main` the default branch (Settings → General → Default
     branch). Until then, new chats may start from an old branch.
   - Deploy `main` to `/var/www/html` once (command under "Deploying changes").
     Until then, the live `index.html` and `members.html` are the rebuilt
     versions from `claude/landing-page-login-rghgnd` (they work, but differ from
     `main`). After deploying, check: log in at `www.`, see the top menu (Home,
     Minecraps, Workflows, Vault), and confirm Vault and Workflows open.
1. **Vault shows Obsidian's Quick Start, not the phone's notes.** Do
   OBSIDIAN-SYNC.md §3 (work laptop): create an empty vault in the browser
   Obsidian, install Self-hosted LiveSync, use the phone's setup URI and
   passphrase, and **fetch from the remote database**.
2. **Second password on the vault** (after the website login): probably the
   Obsidian container's own login *(unconfirmed)*. Owner wants one login.
3. The ob./wf. landing pages and `minecraps.html` still mention "Flying Cocker"
   in their body text (not in the header). The owner asked to remove the name
   from every page. Confirm with the owner whether the body text counts.
4. Security hardening: ufw firewall, key-only SSH, `unattended-upgrades`.
5. Optional: automate deploys (deploy key + script).

## Handy read-only checks

```bash
nginx -t; nginx -T 2>/dev/null | grep -E "server_name|location|proxy_pass|root "; ss -ltnp | grep -E ":8787|:3000|:5984|:5678"; docker ps; systemctl status fc-auth --no-pager | head -5; ls -la /var/www/html /var/www/ob /var/www/wf
```
