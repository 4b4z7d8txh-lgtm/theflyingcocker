# The Flying Cocker

A small members-only website with **real, server-enforced login** via Firebase
Authentication. Approved accounts (that only you can create) sign in on
`index.html` and reach the members area (`members.html`); the private content
lives in Firestore and is released only to a signed-in user.

## Files

| File | Purpose |
|------|---------|
| `index.html` | The plain login page (username + password only), wired to Firebase sign-in. |
| `members.html` | The members home — verifies the login and loads private content from Firestore. |
| `minecraps.html` | Protected sub-page: the family Minecraft (Bedrock) server info and how to join. |
| `assets/members-guard.js` | Shared login gate imported by every members page (redirect to login, reveal page, sign out). |
| `assets/session.js` | Hands the login to the sign-on helper so `wf.`/`ob.` need no second login. |
| `auth-service/` | Small single sign-on helper that runs on the VPS (see SUBDOMAINS.md). |
| `assets/members.css` | Shared members-area styling (top bar, nav, footer) so pages stay consistent. |
| `assets/firebase-config.js` | Your Firebase project config (you paste this in — see SETUP.md). |
| `assets/img/portrait.jpg` | Portrait image (no longer shown on any page). |
| `firestore.rules` | Security rules that protect the members content on the server. |
| `SETUP.md` | Firebase setup (about 15 min, no coding). |
| `VPS-SETUP.md` | **Start here for the server:** how the live site is hosted, the subdomains, single sign-on, and deploying. |
| `CLAUDE.md` | Notes Claude reads automatically at the start of each session. |
| `.claude/skills/wrap-up/` | The `/wrap-up` command: type it at the end of a chat to save the work into `main`. |
| `subdomains/wf/index.html` | Landing page for `wf.theflyingcocker.co.uk` (n8n workflows). |
| `subdomains/ob/index.html` | Landing page for `ob.theflyingcocker.co.uk` (Obsidian vault in the browser). |
| `subdomains/zo/index.html` | Landing page for `zo.theflyingcocker.co.uk` (Zotero file sync settings). |
| `subdomains/shared/landing.css` | Styling shared by the subdomain landing pages. |
| `server-setup.sh` | One-line server setup for the `wf.`/`ob.` subdomains and sign-on (see SUBDOMAINS.md). |
| `obsidian-sync-setup.sh` | Server setup for Obsidian sync (LiveSync via CouchDB) and nightly backups. |
| `OBSIDIAN-SYNC.md` | How the phone + browser Obsidian sync and the backups work, step by step. |
| `zotero-webdav-setup.sh` | One-line server setup for Zotero file sync (WebDAV) on `zo.` and its nightly backups. |
| `ZOTERO-SYNC.md` | How the Zotero file sync works and how to set up Zotero on each device. |
| `SUBDOMAINS.md` | How to run n8n and Obsidian on the VPS and serve the `wf.`/`ob.` subdomains. |
| `MINECRAFT-SERVER.md` | How to run the Bedrock game server on the VPS (`mc.theflyingcocker.co.uk`). |

## Adding another members sub-page

The members area uses one shared login gate, so new protected pages are quick:
copy `minecraps.html`, link `assets/members.css`, and call `guardMembersPage()`
from `assets/members-guard.js` (optionally with a callback to load data once
sign-in is confirmed). Then add a link to it in the `<nav>` of the other members
pages. Every page is protected by the same server-enforced Firebase check.

## Who can see what

Everyone with an account sees everything: the members pages and the `wf.` and
`ob.` subdomains, all from the one sign-in (see SUBDOMAINS.md).

## How it works

1. A member enters their email (the "Username" field) and password on `index.html`.
2. Firebase verifies the password **on Google's servers** and signs them in.
3. `members.html` confirms the session, then fetches the private content from
   **Firestore**, which its security rules release only to a signed-in user.
4. Anyone not signed in is bounced back to the login page and can't read the
   content even by requesting it directly.

## Getting it running

Follow **[SETUP.md](SETUP.md)**. In short: create a free Firebase project, turn
on Email/Password login, disable public sign-up, add your members, paste your
config into `assets/firebase-config.js`, publish the Firestore rules, and add
your content. **The login won't work until SETUP.md is done.**

## Managing members

In the Firebase console → **Authentication → Users**: **Add user** to approve
someone, delete a user to revoke access. No code changes needed.

## Publishing

Because the private data lives in Firestore (not in these files), you can host
the files on **any** static host — Firebase Hosting, GitHub Pages, Netlify — and
the security travels with the data. See SETUP.md step 9.

## Why this is secure

Passwords are never stored in the site files; Firebase checks them server-side.
The members content is served by Firestore only to a signed-in account, enforced
by a rule that runs on Google's servers — so editing the page can't bypass it.
And only accounts you create can log in.
