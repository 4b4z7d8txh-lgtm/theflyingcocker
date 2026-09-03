# The Flying Cocker

A small members-only website: a login landing page (`index.html`) that lets
**approved accounts** into the members area (`members.html`). Everyone else is
kept out.

## Files

| File | Purpose |
|------|---------|
| `index.html` | Login landing page (username + password). |
| `members.html` | The protected site behind the login. |
| `assets/auth.js` | The list of approved users and the sign-in logic. |
| `assets/style.css` | Styling for both pages. |

## How it works

1. A visitor enters a username and password on `index.html`.
2. If they match an approved account, they're sent to `members.html`.
3. `members.html` checks that the visitor is signed in — if not, it sends them
   back to the login page.
4. The **Sign out** button clears the session.

## Adding or changing users

Open `assets/auth.js` and edit the `APPROVED_USERS` list:

```js
var APPROVED_USERS = [
  { username: 'admin',  password: 'change-me-please' },
  { username: 'jane',   password: 'a-good-password'  }
];
```

**Change the default passwords before you publish the site.**

## Publishing

These are plain static files, so any static host works. The easiest is
**GitHub Pages**: in the repo, go to *Settings → Pages*, choose your branch,
and the site is live at `https://<you>.github.io/theflyingcocker/`.

## A note on security

The login is checked **in the browser**, which means the passwords in
`auth.js` are visible to anyone who views the page source. This is enough to
give members a private space and keep casual visitors out, but it is **not**
real security — do not use it to protect sensitive or valuable information.

If you need genuine protection (passwords that can't be seen, real accounts),
the login has to be verified on a **server**. Options include Netlify Identity,
Auth0, Firebase Authentication, Cloudflare Access, or a small backend of your
own. I'm happy to set one of those up if you'd like.
