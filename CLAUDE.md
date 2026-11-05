# Notes for Claude

Read **[VPS-SETUP.md](VPS-SETUP.md)** before helping with this site. It has the
server layout (subdomains `www.`, `ob.`, `wf.`), the single sign-on setup
(fc-auth on port 8787), which files exist only on the server, the deploy
command, and the open to-do list.

Working rules for this project:
- The owner is not a developer and uses SSH **from a phone**. Give every server
  command as a **single line** (pasting loses line breaks). Keep explanations
  in plain language.
- Several live pages exist **only on the server** (see the table in
  VPS-SETUP.md). Never deploy a repo file over a server file without first
  checking that the server copy isn't different. Bring server-only pages into
  the repo before editing them.
- Prefer read-only commands when gathering information, and say so.
- Never ask the owner to print `/opt/fc-auth/service-account.json` or any other secret.
- When you learn something new about the server, update VPS-SETUP.md in the
  same change.
- Deploy branch: `claude/landing-page-login-rghgnd`.
