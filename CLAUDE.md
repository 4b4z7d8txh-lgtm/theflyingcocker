# Notes for Claude

Read **[VPS-SETUP.md](VPS-SETUP.md)** before helping with this site. It has the
server layout (subdomains `www.`, `ob.`, `wf.`, `zo.`), the single sign-on setup
(fc-auth on port 8787), the deploy commands and the open to-do list. For details
see SUBDOMAINS.md, OBSIDIAN-SYNC.md, ZOTERO-SYNC.md and MINECRAFT-SERVER.md.

Working rules for this project:
- **`main` is the only branch to work from and deploy from.** The `claude/...`
  branches are old history.
- The owner is not a developer and uses SSH **from a phone**. Give every server
  command as a **single line** (pasting loses line breaks). Keep explanations
  in plain language.
- Before deploying a file over the server's copy, make sure the repo version
  is the newest one. Anything changed on the server must be brought into the repo.
- Prefer read-only commands when gathering information, and say so.
- Never ask the owner to print `/opt/fc-auth/service-account.json` or any other secret.
- When you learn something new about the server, update VPS-SETUP.md in the
  same change.

At the **start** of a chat: check `git branch -r` for `claude/...` branches
with commits that aren't in `main`
(`git log origin/main..origin/<branch> --oneline`). If you find any, tell
the owner and offer to bring that work into `main` first.

At the **end** of a chat, once the work is done: remind the owner to type
**`/wrap-up`**. That skill (`.claude/skills/wrap-up/`) updates the docs and
merges this chat's work into `main`.
