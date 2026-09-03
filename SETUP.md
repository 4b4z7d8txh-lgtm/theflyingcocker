# Setting up real login for The Flying Cocker

This site uses **Firebase Authentication** (username + password) plus
**Firestore** for the private content. It gives you genuine, server-enforced
security: the members' material lives on Google's servers and is only released
to a signed-in, approved account. Nothing sensitive sits in the website files.

You'll do this once, in the Firebase console. It takes about 15 minutes and
needs no coding. **The login will not work until these steps are done.**

---

## 1. Create a Firebase project

1. Go to <https://console.firebase.google.com> and sign in with a Google account.
2. Click **Add project**, name it (e.g. `the-flying-cocker`), and accept the
   defaults. You can turn Google Analytics **off** — it isn't needed.

## 2. Register the website ("web app")

1. On the project home, click the **web icon** `</>` ("Add app").
2. Give it a nickname (e.g. `Flying Cocker site`) and click **Register app**.
3. Firebase shows you a `firebaseConfig = { ... }` block. **Copy those values.**

## 3. Paste the config into the site

Open **`assets/firebase-config.js`** and replace the `PASTE_..._HERE`
placeholders with the values from step 2. (These values are safe to be public —
your security comes from the next steps, not from hiding them.)

## 4. Turn on Email/Password login

1. In the console, left menu: **Build → Authentication → Get started**.
2. Open the **Sign-in method** tab.
3. Click **Email/Password**, toggle the first switch **On**, and **Save**.

## 5. Lock it to approved people only (important)

This stops anyone from creating their own account — only you can.

1. Still in **Authentication**, open the **Settings** tab → **User actions**.
2. **Uncheck "Enable create (sign-up)"** and save.

Now accounts exist only if *you* add them.

## 6. Add your approved members

1. **Authentication → Users → Add user**.
2. Enter each member's **email** and a **password**, then **Add user**.
3. Repeat for everyone who should have access. (The login page's "Username"
   field is their email address.)

To remove someone's access later, delete their user here.

## 7. Create the Firestore database + rules

1. Left menu: **Build → Firestore Database → Create database**.
2. Choose a location, and start in **production mode** (locked by default).
3. Open the **Rules** tab, replace everything with the contents of
   **`firestore.rules`** (in this repo), and click **Publish**.

## 8. Add the members' content

1. In **Firestore Database → Data**, click **Start collection**.
2. Collection ID: `members`.
3. Add a document with Document ID: `home`.
4. Give it two fields (both type *string*):
   - `heading` — e.g. `Welcome to the club`
   - `body` — the private text your members should see (line breaks are kept).
5. **Save.**

That's the content the members page loads after login. Edit it here anytime;
add more fields or documents as you grow.

---

## 9. Publish the site

Because the private data lives in Firestore (not the files), you can host the
plain files **anywhere** — the security travels with the data. Options:

- **Firebase Hosting** (natural fit, free): install Node, then
  `npm i -g firebase-tools`, `firebase login`, `firebase init hosting`
  (set the public directory to `.`), and `firebase deploy`.
- **GitHub Pages / Netlify / any static host**: just upload these files.
  It's still secure — the members content is never in the files.

## 10. Test it

1. Open the site, sign in with an account you created in step 6 → you reach the
   members area and see your Firestore content.
2. Sign out, then try to open `members.html` directly → you're bounced to login
   and, even in the browser's network tab, the content request is **denied**.

---

## Why this is secure (unlike the old version)

- Passwords are **never** in the website files — Firebase checks them on its
  own servers.
- The private content is served by Firestore **only** to a signed-in user, and
  the rule that enforces this runs on Google's servers, so editing the page
  can't get around it.
- Only accounts **you** create can log in (step 5).

## Want passwordless or Google login instead?

Firebase also supports "email link" (a login link sent to the inbox) and
"Sign in with Google". Say the word and I'll switch the login page over.
