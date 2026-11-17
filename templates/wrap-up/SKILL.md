---
name: wrap-up
description: End-of-chat wrap-up for this repository. Records what was learned in the project's notes, checks that anything changed outside the repo (servers, apps, settings) is written down, commits this chat's work and merges it into the main branch. Use when the owner types /wrap-up or says the chat is finished.
---

# Wrap-up: save this chat's work into the main branch

This is a general template. It works in any repository without changes: it
reads the repo's own notes to learn the details. To install it, copy this file
to `.claude/skills/wrap-up/SKILL.md` in the repository.

The owner may not be a developer and may work from a phone. Explain in plain
language, and give any command they must run themselves as a **single line**
(pasting on a phone loses line breaks).

Do these steps in order. Stop and tell the owner if any step fails. Never
force-push the main branch. Never write secrets (passwords, keys, tokens,
private config files) into any file or message.

## 1. Learn the project's rules

- Read `CLAUDE.md` (and any file it points to) and `README.md`, if present.
  Follow any wrap-up rules found there. They override this template.
- Find the **main branch**: the one `CLAUDE.md` names, otherwise the
  repository's default branch (`git remote show origin | grep 'HEAD branch'`),
  otherwise `main`.
- Find the **notes file(s)**: the docs the project uses to record how things
  are set up (for example a runbook, `SETUP.md`, `NOTES.md`, `docs/`). If
  there are none, use `README.md`.

## 2. Update the notes

Look back over this whole chat and record in the notes file(s):
- anything new learned (paths, settings, versions, services, how something
  works, the cause and fix of a problem, gotchas);
- the **to-do / open items** list: mark done what was finished, add anything
  new that is still open. If the notes have no such list, add a short
  "Open items" section.
- If files were added or removed, update any file list in `README.md`.

Keep the existing style and language of the notes. Short and plain is better.

## 3. Check nothing lives only outside the repo

List everything this chat changed **outside** the repository (on a server, in
an app's settings, in a website dashboard, on the owner's computer).
- If it's a file that belongs in the repo, bring it into the repo with the
  same content.
- If it's a setting that can't live in the repo, make sure step 2 wrote it
  down.
- If unsure whether the repo copy is the newest one, ask the owner rather than
  overwrite.

## 4. Commit

Commit all remaining changes on this chat's branch with a clear message.

## 5. Merge into the main branch

- `git fetch origin <main>`
- If this chat's branch isn't the main branch:
  `git checkout <main> && git pull origin <main>`, then
  `git merge --no-ff <this chat's branch>`.
- On conflicts: keep the newest working version of each file. If unsure,
  stop and ask the owner. Don't guess with files that run something live.
- `git push -u origin <main>` (retry only on network errors).
- If pushing to the main branch is refused (protected branch, no permission),
  push this chat's branch instead and tell the owner it needs to be merged
  on GitHub.

## 6. Report to the owner, briefly

- what changed in this chat, in plain language;
- whether anything still needs to be deployed or done by hand, as
  ready-to-paste single-line commands taken from the notes;
- the remaining open items.
