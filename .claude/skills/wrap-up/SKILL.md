---
name: wrap-up
description: End-of-chat wrap-up for The Flying Cocker site. Records what was learned in the docs, checks the server and repo match, merges this chat's branch into main and pushes it. Use when the owner types /wrap-up or says the chat is finished.
---

# Wrap-up: put this chat's work into `main`

The owner is not a developer and uses SSH from a phone. Explain in plain
language and give any server command as a **single line**.

Do these steps in order. Stop and tell the owner if any step fails. Never
force-push `main`.

1. **Update the docs.** In `VPS-SETUP.md`, record anything new learned about
   the server in this chat: paths, ports, services, nginx, Docker, gotchas.
   Update the **Open items** list: remove what's done and add anything new.
   Update the README file table if files were added or removed. Never write
   secrets (passwords, keys, tokens, the contents of `service-account.json`).

2. **Check the repo matches the server.** List every file this chat deployed
   or changed directly on the server. Each one must now be in the repo with
   the same content. If something was changed on the server but not in the
   repo, bring it into the repo, or list it clearly for the owner.

3. **Commit** any remaining changes on this chat's branch.

4. **Merge into `main`:**
   - `git fetch origin main`
   - If this chat's branch isn't `main`: `git checkout main && git pull origin main`, then
     `git merge --no-ff <this chat's branch>`.
   - On conflicts, keep the newest working version of each file. If unsure,
     stop and ask the owner. Don't guess with live-site files.
   - `git push -u origin main` (retry on network errors only).

5. **Report to the owner**, briefly:
   - what changed in this chat (plain language)
   - whether the live server still needs a deploy, as a ready-to-paste
     single-line command from VPS-SETUP.md using the `main` branch
   - the remaining open items
