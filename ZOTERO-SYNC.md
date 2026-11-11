# Zotero file sync — `zo.theflyingcocker.co.uk` (WebDAV)

> Plain-language summary: Zotero syncs two things. Your **library** (items,
> notes, tags, collections) keeps syncing through your free zotero.org account.
> Your **files** (PDFs, snapshots) sync to your own server at
> `zo.theflyingcocker.co.uk/dav`, so there's no storage plan to pay for.

```
 Zotero desktop (laptop)              Zotero app (iPhone / iPad)
          │   WebDAV over HTTPS, username "zotero" + password   │
          └────────────►  zo.theflyingcocker.co.uk/dav  ◄────────┘
                                  │ nginx (HTTPS)
                                  ▼
            WebDAV server in Docker (hacdias/webdav), 127.0.0.1:8090
            files in /opt/zotero-webdav/data/zotero/
                                  │
                                  ▼
            Nightly backup 03:30 → /root/backups/zotero (30 days)
```

| Address | What | Who gets in |
|---|---|---|
| `https://zo.theflyingcocker.co.uk/` | Landing page with the Zotero settings | Members (website login) |
| `https://zo.theflyingcocker.co.uk/dav/` | The WebDAV folder Zotero uses | Username `zotero` + its own password (the Zotero app can't use the website login) |

Only for the owner's own library (one account). Group libraries can't use
WebDAV: their files always sync through zotero.org.

---

## 1. DNS (once)

Where the domain's DNS is managed (same place as `www`, `ob`, `wf`, `mc`), add:

| Type | Name | Value | TTL |
|---|---|---|---|
| A | `zo` | the VPS's IP (same as `ob`) | 3600 |

Wait about 10 minutes. Check on the server (read-only): `getent hosts zo.theflyingcocker.co.uk`

## 2. Server (once)

Paste this one line into SSH as `root`:

```
curl -fsSL https://raw.githubusercontent.com/4b4z7d8txh-lgtm/theflyingcocker/main/zotero-webdav-setup.sh -o /root/zo-setup.sh && bash /root/zo-setup.sh
```

`zotero-webdav-setup.sh`:

1. checks DNS for `zo.` points at this server and port 8090 is free;
2. creates `/opt/zotero-webdav/` (`compose.yaml`, `config.yml` with the
   password stored hashed, `credentials.txt` readable by root only, and
   `data/zotero/` for the files), then starts the WebDAV container. It runs as
   the unprivileged user `nobody`, read-only apart from `data/`;
3. adds the nginx site `zo.theflyingcocker.co.uk` (landing page behind the
   members gate, `/dav/` with the gate off) via the snippet
   `/etc/nginx/snippets/fc-zotero-dav.conf`. It only reloads nginx if
   `nginx -t` passes;
4. gets the HTTPS certificate with certbot;
5. deploys the landing page from `main` into `/var/www/zo`;
6. tests the public address, schedules the nightly backup and runs it once.

It ends with **ALL DONE** and the Zotero URL, username and password. Show them
again any time with:

```
cat /opt/zotero-webdav/credentials.txt
```

Safe to run again: it keeps the same password and files.

## 3. Zotero desktop (Windows / Mac)

Zotero → **Settings** (Mac: Zotero → Settings; Windows: Edit → Settings) → **Sync**:

1. **Data Syncing:** signed in with your zotero.org account (leave as is).
2. **File Syncing → Sync attachment files in My Library using:** **WebDAV**.
3. **URL:** choose `https`, then type `zo.theflyingcocker.co.uk/dav`
   (Zotero adds `/zotero/` itself).
4. **Username:** `zotero` · **Password:** from ALL DONE.
5. Press **Verify Server** → it should say the server is set up correctly.
   Then press the green sync arrow.

The first sync uploads every attachment (about 100 MB now), so give it a few
minutes.

## 4. Zotero on iPhone / iPad

Zotero app → **Settings** (gear) → **Account** → **File Syncing**:

1. **Sync attachment files in My Library using:** **WebDAV**.
2. The address line shows `https://` before the box and `/zotero/` after it.
   In the box type **`zo.theflyingcocker.co.uk/dav`** (don't forget `/dav`).
3. **Username:** **`zotero`**, not your zotero.org email.
4. **Password:** from ALL DONE (not your zotero.org password).
5. **Verify Server**.

`Zotero.AFResponseError error 1` on Verify Server usually means `/dav` is
missing from the address, or the username/password is wrong.

## 5. Moving files off zotero.org storage

If you used zotero.org's free 300 MB before: once the first WebDAV sync has
finished, open a few PDFs on a second device. If they open, you can delete the
old copies at zotero.org → **Settings → Storage → Purge attachment files**
(this doesn't touch your WebDAV files or your library).

## 6. Test checklist (private/incognito tab)

1. `https://zo.theflyingcocker.co.uk/` → the website login, then the landing page.
2. `https://zo.theflyingcocker.co.uk/dav/` → asks for a username/password, not the website login.
3. Zotero desktop → **Verify Server** succeeds.
4. Add a PDF on the laptop, sync → it opens on the phone.
5. On the server (read-only): `ls /opt/zotero-webdav/data/zotero | head` shows `.zip` and `.prop` files.

---

## Troubleshooting (read-only)

```
docker ps --filter name=zotero-webdav; docker logs --tail 30 zotero-webdav; curl -s -o /dev/null -w "%{http_code}\n" -X PROPFIND https://zo.theflyingcocker.co.uk/dav/zotero/
```

The last number should be `401` (asks for the password).

- **Verify Server says the password is wrong:** compare with
  `cat /opt/zotero-webdav/credentials.txt`. Watch for spaces at the end.
- **"File too large":** nginx accepts files up to 1 GB at `/dav/`. Change
  `client_max_body_size` in `/etc/nginx/snippets/fc-zotero-dav.conf` in the
  repo script, then re-run it.
- **New password:** `rm /opt/zotero-webdav/credentials.txt`, then run the
  setup line again. Put the new password into Zotero on every device.

## Backups

Every night at 03:30, `/usr/local/bin/zotero-backup.sh` copies
`/opt/zotero-webdav/data` into `/root/backups/zotero/<date>/` and keeps the
newest 30 days. Unchanged files are shared between days (hard links), so 30
days take about as much space as one. Log: `/var/log/zotero-backup.log`.

Restore a file or everything (stop Zotero syncing first):

```
rsync -a /root/backups/zotero/YYYY-MM-DD/ /opt/zotero-webdav/data/ && chown -R 65534:65534 /opt/zotero-webdav/data
```

## Updating the WebDAV server

The image is pinned (`hacdias/webdav:v5.17.1` in the script). To update, change
`IMAGE=` in `zotero-webdav-setup.sh` in the repo, merge to `main`, and run the
setup line again.

## Security notes

- The WebDAV server listens on `127.0.0.1:8090` only. Never open 8090 in a firewall.
- The password is long and random and stored hashed in `config.yml`.
  `credentials.txt` is readable by root only.
- Files are **not** end-to-end encrypted (Zotero's WebDAV has no such option),
  so anyone with root on the VPS can read them.
- Not done yet (owner chose later): a rate limit or fail2ban on `/dav/` against
  password guessing. Tracked in VPS-SETUP.md open items.

## Remove it

One line (keeps the files and backups):

```
cd /opt/zotero-webdav && docker compose down; rm -f /etc/nginx/sites-enabled/zo.theflyingcocker.co.uk /etc/cron.d/zotero-backup; nginx -t && systemctl reload nginx
```

Then switch Zotero back to "Zotero" storage.
