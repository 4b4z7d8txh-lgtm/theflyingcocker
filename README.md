# The Flying Cocker

A small members-only website with **real, server-enforced login** via Firebase
Authentication. Approved accounts (that only you can create) sign in on
`index.html` and reach the members area (`members.html`); the private content
lives in Firestore and is released only to a signed-in user.

## Files

| File | Purpose |
|------|---------|
| `index.html` | The login landing page (the "Flying Cocker" design), wired to Firebase sign-in. |
| `members.html` | The members area — verifies the login and loads private content from Firestore. |
| `assets/firebase-config.js` | Your Firebase project config (you paste this in — see SETUP.md). |
| `assets/img/portrait.jpg` | The portrait shown on the login card. |
| `firestore.rules` | Security rules that protect the members content on the server. |
| `SETUP.md` | **Start here** — step-by-step Firebase setup (about 15 min, no coding). |

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
