# VPS runbook — The Flying Cocker

How the live site is hosted and how to deploy changes. This is the site at
**https://www.theflyingcocker.co.uk**.

> Plain-language summary: the website files live in a folder on a Linux server
> (a Fasthosts VPS). To update the site, you copy the latest files from GitHub
> into that folder. Nginx (the web server) then serves them to visitors.

---

## The server at a glance

| Thing | Value |
|-------|-------|
| Host | Fasthosts VPS |
| OS | Ubuntu 24.04 LTS |
| Web server | Nginx |
| HTTPS | Enabled via Certbot / Let's Encrypt (auto-renews) |
| Domain | `theflyingcocker.co.uk` and `www.theflyingcocker.co.uk` |
| Web root (docroot) | `/var/www/html` |
| Files owned by | user `deployuser`, group `www-data` |
| You log in via | SSH as `root` (`ssh root@YOUR_SERVER_IP`) |

The login page is served at the site **root** (`/`). The old mockup is kept as
`/var/www/html/index.html.mockup.bak`. The path `/login` is not used.

## What's in the web root

```
/var/www/html/
  index.html                 <- login page (Firebase email/password sign-in)
  members.html               <- protected members home; loads content from Firestore
  minecraps.html             <- protected sub-page: family Minecraft server info
  assets/
    firebase-config.js       <- Firebase web config (public by design)
    members-guard.js         <- shared login gate imported by every members page
    members.css              <- shared members-area styling (topbar, nav, footer)
    img/portrait.jpg         <- the login portrait
  index.html.mockup.bak      <- backup of the original mockup (not served as a page)
```

Any new protected sub-page goes in `/var/www/html/` too. The easy, repeatable
recipe: copy `minecraps.html` as a starting point, link `assets/members.css`, and
call `guardMembersPage()` from `assets/members-guard.js` — that single shared
module does the "redirect to login if not signed in" check, reveals the page and
wires up Sign out. Then add a link to the new page in the `<nav>` of the other
members pages.

> The actual **Minecraft (Bedrock) game server** is a separate program on the
> VPS, not a web page — see **[MINECRAFT-SERVER.md](MINECRAFT-SERVER.md)** to set
> it up (`mc.theflyingcocker.co.uk`, UDP 19132). `minecraps.html` is just the
> members page that shows the kids how to connect.

---

## Deploying changes

All site changes are committed to GitHub first, then pulled onto the server.

- **Repo:** `4b4z7d8txh-lgtm/theflyingcocker`
- **Branch:** `claude/flying-cocker-sub-pages-4kdpni` (current active branch —
  the members sub-pages work lives here)
- Because the repo files are publicly readable, the server downloads them with
  `curl` from the raw GitHub URL — no keys or passwords needed.

### To deploy (run on the server, connected as `root`)

Edit the `FILES` line to list exactly the files you changed or added, then paste
the whole block:

```bash
cd /var/www/html
BASE="https://raw.githubusercontent.com/4b4z7d8txh-lgtm/theflyingcocker/claude/flying-cocker-sub-pages-4kdpni"

# List the files to (re)download — add new sub-pages here as you create them:
FILES="index.html members.html minecraps.html assets/firebase-config.js assets/members-guard.js assets/members.css assets/img/portrait.jpg"

for f in $FILES; do
  mkdir -p "$(dirname "$f")"
  curl -fsSL "$BASE/$f" -o "$f" && echo "updated $f" || echo "FAILED $f"
done

# Fix ownership and permissions
chown -R deployuser:www-data /var/www/html
find /var/www/html -type d -exec chmod 755 {} \;
find /var/www/html -type f -exec chmod 644 {} \;

echo "Done. Current files:"; ls -laR /var/www/html
```

### After deploying
- Test in a **private/incognito window** (avoids seeing a cached old page).
- Nginx serves the new files immediately — no restart needed.
- If a page looks stale, hard-refresh with `Ctrl+F5`.

> Note: pushing to GitHub alone does **not** update the live site. You must run
> the deploy block on the server for changes to appear.

---

## Authentication (Firebase) — reference

- **Firebase project id:** `theflyingcocker`
- **Sign-in:** Email/Password. Public sign-up is **disabled** — only the owner
  creates accounts in Firebase console → Authentication → Users.
- **Private content:** Firestore collection `members`, document `home`, string
  fields `heading` and `body`. `members.html` loads it after login.
- **Firestore rules** (`firestore.rules`): the `members` content is readable only
  when signed in; all writes and everything else are denied.
- If a login ever errors with **"unauthorized domain,"** add
  `theflyingcocker.co.uk` (and `www.`) in Firebase console → Authentication →
  Settings → Authorized domains.

---

## Still to do (not done yet)

1. **Deploy workflow** — the `curl` steps above are manual; could be scripted or
   automated later.
2. **Security hardening** — firewall (ufw), SSH hardening (key-only login,
   disable root password login), and automatic security updates
   (`unattended-upgrades`). Do this soon: the server is exposed to the internet.
3. Consider making the GitHub repo private and switching the server to a
   read-only **deploy key** instead of public `curl` (optional).

---

## Handy checks (all read-only)

```bash
# Is Nginx happy?
nginx -t && systemctl status nginx --no-pager

# What's in the web root?
ls -laR /var/www/html

# Recent Nginx errors (last 30 lines)
tail -n 30 /var/log/nginx/error.log

# Is HTTPS certificate current / when does it renew?
certbot certificates
```
