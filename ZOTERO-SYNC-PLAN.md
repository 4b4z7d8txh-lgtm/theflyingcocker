# Zotero WebDAV sync on `zo.` — integration plan (for review)

> **Status: plan only. Nothing has been changed on the server or in `main`.**
> Once you approve it (or tell me what to change), I'll write the setup script,
> landing page and guide, and you run one line on the server.

## In plain language

Zotero syncs two different things:

| What | Where it syncs | Changes with this plan? |
|---|---|---|
| Your **library** — items, tags, collections, notes | zotero.org (free account) | **No.** You still sign in to Zotero's own sync. This part is free and unlimited. |
| Your **files** — PDFs, snapshots, other attachments | zotero.org storage (300 MB free) **or your own WebDAV server** | **Yes.** Files go to `zo.theflyingcocker.co.uk` on your VPS instead. No storage limit except the VPS disk, no subscription. |

So after this, Zotero on every device keeps using your zotero.org login for the
library, and uses your own server for the PDFs.

```
 Zotero desktop (laptop)          Zotero on iPhone / iPad
          │  WebDAV (HTTPS, username + password)  │
          └────────►  zo.theflyingcocker.co.uk/dav  ◄─────┘
                               │ nginx (HTTPS)
                               ▼
                 WebDAV server in Docker, 127.0.0.1:8090
                 files in /opt/zotero-webdav/data/zotero/
                               │
                               ▼
               Nightly backup 03:30 → /root/backups/zotero (30 days)
```

## Key decisions (please check these)

1. **Login: a separate Zotero username + password, not the website login.**
   The Zotero app can't use the website's sign-in cookie — it can only send a
   username and password (same reason the Obsidian CouchDB sync has its own
   password, see OBSIDIAN-SYNC.md). The script creates the account `zotero`
   with a long random password and shows it once at the end. You type it into
   Zotero on each device, once.

2. **WebDAV server: a small program in Docker** (`hacdias/webdav`, pinned to a
   fixed version), listening only on `127.0.0.1:8090`, with nginx in front for
   HTTPS. This matches how n8n, Obsidian and CouchDB already run, doesn't
   change the nginx installation that the other sites depend on, and can be
   removed cleanly (`docker compose down`).
   - *Alternative:* nginx's own WebDAV module (needs the extra package
     `libnginx-mod-http-dav-ext`). No container, but it changes nginx itself
     for all sites. I don't recommend it unless the VPS is short on memory
     (the Docker one uses ~20 MB RAM).

3. **Addresses on `zo.`:**
   - `https://zo.theflyingcocker.co.uk/` — small landing page with setup
     instructions, **members only** (website login, same as `ob.`/`wf.`).
   - `https://zo.theflyingcocker.co.uk/dav/` — the WebDAV folder. **Not**
     behind the website login (the app can't do it); protected by the Zotero
     password instead. Zotero adds `/zotero/` itself, so files end up at
     `/dav/zotero/`.

4. **One shared account** for your own library. If other family members want
   their own Zotero file sync, each needs their own account and folder — tell
   me now if so and I'll build that in.

## What will be added to the repo (after your approval)

| File | Purpose |
|---|---|
| `zotero-webdav-setup.sh` | One-line server setup (steps below). Safe to run again. |
| `subdomains/zo/index.html` | Landing page for `zo.` (same look as `ob.`/`wf.`, uses `subdomains/shared/landing.css`). |
| `ZOTERO-SYNC.md` | The finished guide: server, Zotero desktop, iPhone/iPad, backups, troubleshooting. Replaces this plan. |
| `VPS-SETUP.md`, `SUBDOMAINS.md` | Add `zo.` to the subdomain tables, ports list, deploy and backup commands. |
| `members.html`, `minecraps.html` *(optional)* | Add a "Library" link to the members menu. Say if you want it. |

## Server steps (what the script will do)

**Before the script — you do these:**

1. **DNS:** add an **A record** `zo` → the VPS IP, in the same place as `www`,
   `ob`, `wf` and `mc`. Check on the server (read-only):
   `dig +short zo.theflyingcocker.co.uk`
2. **Space check** (read-only) so we know how much room your PDFs have:
   `df -h /; free -h; ss -ltnp | grep -E ':8090' || echo "port 8090 free"`

**The script (`zotero-webdav-setup.sh`), run with one pasted line:**

1. Stops with a clear message if DNS for `zo.` doesn't point at this server,
   or port 8090 is taken.
2. Creates `/opt/zotero-webdav/` with:
   - `compose.yaml` — the WebDAV container, port `127.0.0.1:8090` only,
     restarts automatically, files in `./data`.
   - `config.yml` — one user `zotero`, password stored **hashed** (bcrypt),
     read/write access to `/data` only.
   - `credentials.txt` (root-only, `chmod 600`) — the plain password, so you
     can look it up later with `cat /opt/zotero-webdav/credentials.txt`.
   - `data/zotero/` — created ready, so Zotero doesn't have to.
3. Starts the container and checks it answers.
4. Writes `/etc/nginx/sites-available/zo.theflyingcocker.co.uk`:
   - `/` → `/var/www/zo` landing page, with the members gate
     (`include snippets/fc-admin-gate.conf;`).
   - `/dav/` → `auth_request off;` then proxied to `127.0.0.1:8090`, with
     `client_max_body_size 1g` (large PDFs), request/response buffering off,
     long timeouts, and the WebDAV methods passed through untouched
     (`PROPFIND`, `PUT`, `DELETE`, `MKCOL`, `MOVE`, `OPTIONS`).
   - Runs `nginx -t` and only reloads nginx if the test passes, so a mistake
     can't take down the other sites.
5. Gets the HTTPS certificate: `certbot --nginx -d zo.theflyingcocker.co.uk`.
6. Deploys the landing page from `main` into `/var/www/zo` (same `curl`
   method as `ob.`/`wf.`) and sets owner `deployuser:www-data`.
7. Adds a nightly backup (cron, 03:30, after the Obsidian one at 03:15):
   `tar` of `/opt/zotero-webdav/data` into `/root/backups/zotero/`, keeps 30 days.
8. Prints **ALL DONE** with the three Zotero settings: URL, username, password.

## Zotero settings (each device, once)

**Desktop (Windows/Mac):** Zotero → *Settings → Sync*
1. Sign in with your **zotero.org** account (for the library) if not already.
2. *File Syncing → My Library → Sync attachment files using:* **WebDAV**
3. URL: `https` + `zo.theflyingcocker.co.uk/dav` · Username: `zotero` ·
   Password: from ALL DONE.
4. **Verify Server** → should say it works. Then *Sync*.

**iPhone/iPad (Zotero app):** *Settings → Account → File Syncing → WebDAV*,
same three details, then *Verify*.

**Moving existing PDFs off zotero.org storage (if you've used it):** after
switching to WebDAV, Zotero uploads each file to your server as it syncs. Once
everything is on `zo.`, you can delete the old copies at zotero.org →
*Settings → Storage* to free that space. *Do this only after checking a few
PDFs open on a second device.*

## Testing checklist

1. `https://zo.theflyingcocker.co.uk/` in a private tab → sends you to the
   website login, then back to the landing page.
2. `https://zo.theflyingcocker.co.uk/dav/` in a browser → asks for a
   username/password (not the website login).
3. Zotero desktop → **Verify Server** succeeds.
4. Add a PDF on the laptop, sync → it appears on the phone and opens.
5. On the server (read-only): `ls /opt/zotero-webdav/data/zotero | head` shows
   `.zip` and `.prop` files.

## Security

- WebDAV only reachable over HTTPS through nginx; the container listens on
  `127.0.0.1` only. Never open port 8090 in the firewall.
- Long random password (32+ characters), stored hashed in the config.
- **Optional extra I'd suggest:** an nginx rate limit on `/dav/` and/or
  `fail2ban` for repeated wrong passwords. This fits with open item 4 in
  VPS-SETUP.md (firewall / SSH hardening).
- Your files are not encrypted on the server (Zotero's WebDAV has no
  end-to-end encryption). Anyone with root on the VPS can read them —
  same as the website and vault today.

## Undo

One line removes it all except the backups:
`cd /opt/zotero-webdav && docker compose down; rm -f /etc/nginx/sites-enabled/zo.theflyingcocker.co.uk; nginx -t && systemctl reload nginx`
(then switch Zotero back to "Zotero" storage). Data stays in
`/opt/zotero-webdav/data` until you delete it.

## Questions for you

1. **Just you, or other family members too** (each with their own files)?
2. **Roughly how big** is your PDF collection? (Zotero desktop → *Settings →
   Advanced → Files and Folders → Show Data Directory* → size of the
   `storage` folder.) I'll compare it with the `df -h` result.
3. **Members menu link** to `zo.` — yes or no?
4. OK with the **Docker WebDAV server** (recommended), or prefer nginx's own module?
5. Rate limit / fail2ban now, or later with the other security work?
