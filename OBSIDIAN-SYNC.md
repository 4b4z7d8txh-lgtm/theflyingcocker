# Obsidian sync — phone + work laptop, no extra cost

```
 iPhone — Obsidian app (most notes)            Work laptop — any browser
 vault stored "On My iPhone"                   ob.theflyingcocker.co.uk → Obsidian in the browser
          │  Self-hosted LiveSync plugin                │  Self-hosted LiveSync plugin
          └──────────────►  CouchDB on the VPS  ◄───────┘
                     https://ob.theflyingcocker.co.uk/couchdb
                                   │
                                   ▼
             Nightly backup 03:15 → /root/backups/obsidian (30 days)
             + Markdown copy pushed to a private GitHub repo (optional)
```

- **Sync** goes through the CouchDB that already runs on the VPS
  (`couchdb-for-obsidian`). The phone keeps working offline and catches up when
  back online.
- **iCloud's job** is only the normal **iPhone iCloud Backup** (which includes
  the Obsidian vault stored "On My iPhone"). Don't also put the vault in iCloud
  Drive — two sync systems on one vault cause duplicates and lost edits.
- Everything is free: LiveSync, CouchDB, a private GitHub repo, and the VPS you
  already have.

---

## 1. Server (once)

Paste this one line into SSH as `root`:

```
curl -fsSL https://raw.githubusercontent.com/4b4z7d8txh-lgtm/theflyingcocker/claude/wf-ob-landing-pages-2zcq7f/obsidian-sync-setup.sh -o /root/ob-sync-setup.sh && bash /root/ob-sync-setup.sh
```

It (`obsidian-sync-setup.sh`):

1. applies the CouchDB settings LiveSync needs and creates a dedicated sync
   user `obsidian` with a random password, and a database `obsidian-vault`
   that only that user can use;
2. publishes CouchDB at `https://ob.theflyingcocker.co.uk/couchdb/` — protected
   by that username/password (the app can't use the website sign-in);
3. schedules the nightly backup;
4. optionally connects a private GitHub repo for an off-server copy. It shows
   a key and asks for the repo name — or press Enter to skip and run the script
   again later. To set it up: on GitHub create a new **private**, empty repo
   (e.g. `obsidian-vault`) → **Settings → Deploy keys → Add deploy key** →
   paste the key, tick **Allow write access** → type `owner/name` in SSH.

It ends with **ALL DONE** and the four LiveSync details (server URI, username,
password, database name). Show them again any time with:

```
cat /root/obsidian-sync/livesync-credentials.txt
```

## 2. iPhone (first — your main device)

1. **Vault location:** the vault must be stored **On My iPhone**, not in
   iCloud. If your current vault is in iCloud: create a new vault "On My
   iPhone", then in the Files app move your notes from the iCloud
   `Obsidian/<vault>` folder into `On My iPhone/Obsidian/<new vault>`.
2. In Obsidian: **Settings → Community plugins → Turn on community plugins →
   Browse**, search **Self-hosted LiveSync**, **Install**, **Enable**.
3. Open the plugin's setup and choose to enter the server details manually
   (CouchDB):
   - **Server URI:** `https://ob.theflyingcocker.co.uk/couchdb`
   - **Username / Password / Database name:** from the server's ALL DONE screen
   - Test the connection — it should succeed. If it offers to "check/fix
     database configuration", you can skip it: the server script already
     applied those settings (that check needs the admin account).
4. **Turn on End-to-End Encryption** and choose a passphrase. Save it in your
   password manager — without it the synced notes can't be read, even by you.
5. Choose the **LiveSync** sync mode, and when asked, this is the **first
   device**: let it **upload / initialise the remote database** from this vault.
6. In the plugin settings, use **Copy setup URI** (it asks for a separate
   one-off passphrase that protects the URI). Send that URI to yourself (e.g.
   by email) for the laptop step.

## 3. Work laptop (browser)

1. Open `https://ob.theflyingcocker.co.uk` → **Open the vault** (website
   sign-in only).
2. In the browser Obsidian, **create a new empty vault**, e.g. `Vault`, in
   the default location (it's saved on the server, under `/config`).
3. Install and enable **Self-hosted LiveSync** as on the phone.
4. Choose **Use setup URI**, paste the URI from step 2.6 and its passphrase.
   When asked, this is **not** the first device: **fetch from the remote
   database**. (Or enter the same four details + the End-to-End passphrase by
   hand.)
5. Your phone notes appear within a minute; edits sync both ways from now on.

The browser Obsidian normally keeps running on the server, so it keeps syncing
even when the laptop is closed — which is also what makes the plain-Markdown backup
below always up to date.

> Check your employer's rules before writing work material into a personal
> notes system from the work laptop.

---

## Backups

`/usr/local/bin/obsidian-backup.sh`, every night at 03:15:

| What | Where | Kept |
|------|-------|------|
| CouchDB data (everything LiveSync holds) | `/root/backups/obsidian/couchdb-DATE.tgz` | 30 days |
| Plain-Markdown copy of the browser vault | `/root/backups/obsidian/vault-NAME-DATE.tgz` | 30 days |
| Same Markdown, with full history | your private GitHub repo (if connected) | forever |

LiveSync's own settings (which contain the sync password and passphrase) and
per-device window layouts are never put in the backups or on GitHub.

```bash
/usr/local/bin/obsidian-backup.sh          # run a backup now
tail -n 20 /var/log/obsidian-backup.log    # did last night's run work?
ls -lh /root/backups/obsidian              # what's kept
```

**Restoring:** the easiest copy is GitHub (or a `vault-*.tgz`) — it's ordinary
Markdown: open it as a vault in any Obsidian, then set LiveSync up again as a
"first device" to refill the server.

## Troubleshooting

- **Phone can't connect:** open `https://ob.theflyingcocker.co.uk/couchdb/` in
  Safari — it should ask for a username/password (use the sync user). If not,
  run the server script again and send the output.
- **"Unauthorized":** check the username/password with
  `cat /root/obsidian-sync/livesync-credentials.txt`.
- **Everything else** (sync conflicts, plugin options): the plugin's own docs at
  <https://github.com/vrtmrz/obsidian-livesync>.
