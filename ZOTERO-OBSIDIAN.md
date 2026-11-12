# Zotero notes → Obsidian (automatic)

> Plain-language summary: you keep reading and taking notes in the **Zotero
> app on your iPhone**. Every 15 minutes the server copies your notes and
> highlights into Obsidian, one note per book or article, in a folder called
> **Zotero**. You don't need Zotero on a computer, and nothing is ever
> changed in Zotero.

```
Zotero app (iPhone)  ──syncs by itself──►  zotero.org
                                              │  every 15 min, read-only key
                                              ▼
                       /usr/local/bin/zotero-to-obsidian  (on the VPS)
                                              │  writes Markdown files
                                              ▼
            browser Obsidian's vault: /opt/obsidian/config/<vault>/Zotero/
                                              │  Self-hosted LiveSync
                                              ▼
                                   Obsidian (iPhone)
```

The program can't write into the sync database directly (LiveSync keeps it
encrypted and in pieces), so it puts the files in the **browser Obsidian's**
vault on the server, and that Obsidian sends them on. That's why
OBSIDIAN-SYNC.md section 3 must be done first.

## What you get

- `Zotero/Author Year – Title.md` for every book/article that has highlights
  or notes: title, authors, year, ISBN/DOI, a link to the item on zotero.org,
  then **Highlights** (in page order, with page numbers, your comments and
  tags) and **Notes** (your Zotero notes for that item).
- `Zotero/Notes/<first line>.md` for each standalone note (not attached to an item).
- Each file has a line `<!-- zotero:end … -->`. **Above it** is rewritten
  from Zotero every time something changes. **Below it** ("My thoughts") is
  yours: the program never touches it. If a title changes in Zotero, the file
  is renamed and your thoughts move with it.
- Things in the Zotero **trash** disappear from the note. A book with no
  notes or highlights gets no file.
- Drawings and image highlights show as a line "open it in Zotero to see it".

Don't edit above the `zotero:end` line (it gets replaced). If you delete that
line, the program leaves that file alone from then on.

## Set up (once)

**Before you start:** OBSIDIAN-SYNC.md section 3, so the browser Obsidian has
a vault that syncs with your phone.

**1. Make a Zotero key** (on the phone, in Safari):
zotero.org → log in → **Settings → Security → Create new private key**.
- Name: `Obsidian server`
- Tick **Allow library access** and **Allow notes access**. Leave
  "Allow write access" and the group settings off.
- **Save Key**, then copy the key (about 24 letters and numbers). Keep it out
  of chats and emails: you'll paste it straight into SSH.

**2. Paste this one line into SSH** as `root`:

```
curl -fsSL https://raw.githubusercontent.com/4b4z7d8txh-lgtm/theflyingcocker/main/zotero-obsidian-setup.sh -o /root/zo-ob-setup.sh && bash /root/zo-ob-setup.sh
```

It finds the vault (asks if there's more than one), asks for the key (it stays
hidden while you paste), checks it with zotero.org, installs the program,
schedules it every 15 minutes and runs it once. It ends with **ALL DONE**.

**3. On the phone:** open Obsidian and wait a minute: a **Zotero** folder appears.

Safe to run the line again (to update the program, it keeps the key).

## Everyday use

Nothing to do. Make a highlight or note in the Zotero app; it reaches
Obsidian within about 15–20 minutes (Zotero syncs, then the next run, then
LiveSync). Make sure the Zotero app has synced (pull down in the library).

## Handy commands (one line each)

| What | Command |
|---|---|
| Did it run? (read-only) | `tail -n 20 /var/log/zotero-to-obsidian.log` |
| Run now | `flock /run/zotero-to-obsidian.lock zotero-to-obsidian` |
| Rebuild every file (your thoughts are kept) | `flock /run/zotero-to-obsidian.lock zotero-to-obsidian --full` |
| Use a new key | `rm /opt/zotero-obsidian/config.json && bash /root/zo-ob-setup.sh` |
| Pause it | `rm /etc/cron.d/zotero-to-obsidian` (run the setup line to turn it back on) |

## Files on the server

| Path | What |
|---|---|
| `/usr/local/bin/zotero-to-obsidian` | The program (repo: `zotero-to-obsidian.py`, Python, no extra packages) |
| `/opt/zotero-obsidian/config.json` | Key, zotero.org user id, vault path. **Secret, root only.** Never print it. |
| `/opt/zotero-obsidian/state.json` | What's been copied already (library version, which file is which item) |
| `/etc/cron.d/zotero-to-obsidian` | Every 15 minutes, with a lock so two runs never overlap |
| `/var/log/zotero-to-obsidian.log` | Log, rotated weekly (`/etc/logrotate.d/zotero-to-obsidian`) |

The notes themselves are in the vault, so the nightly Obsidian backup
(OBSIDIAN-SYNC.md) already covers them.

## Troubleshooting

- **`PROBLEM: zotero.org refused the key (403)`**: the key was deleted or
  lacks "notes access". Make a new one, then use the "new key" line above.
- **Files are on the server but not on the phone:** the browser Obsidian
  isn't syncing. Open `ob.…/app/`, check LiveSync is on (OBSIDIAN-SYNC.md §3).
  Read-only check that the files exist: `ls "/opt/obsidian/config/"*/Zotero | head`
- **`SKIPPED (the zotero:end line was removed…)`**: put the line back (copy it
  from another Zotero note) or delete the file and run `--full`.
- **A highlight is missing:** check the Zotero app has synced, then "Run now".

## Notes

- One-way only. Read-only key. Only your own library ("My Library"), not groups.
- Old note files aren't deleted when an item is deleted in Zotero (in case
  you wrote thoughts in them). Delete them in Obsidian if you don't want them.
