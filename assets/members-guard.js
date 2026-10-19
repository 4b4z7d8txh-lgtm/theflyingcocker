// -------------------------------------------------------------------------
// Shared login gate for The Flying Cocker members area
// -------------------------------------------------------------------------
// Every protected members page imports this one module so the login check
// lives in a single place. It:
//   1. Initialises Firebase.
//   2. Redirects to the login page (index.html) if nobody is signed in.
//   3. On admin-only pages, sends non-admin members to Minecraps.
//   4. Reveals the page (#app) once access is confirmed, and shows the
//      admin-only nav links (marked data-admin-only) to the admin.
//   5. Fills in #welcome and wires up the #signout button, if present.
//
// Usage in a members page:
//
//   <script type="module">
//     import { guardMembersPage } from './assets/members-guard.js';
//     guardMembersPage();                    // any signed-in member
//     guardMembersPage(null, { adminOnly: true });   // admin only
//     // or, to run code once access is confirmed:
//     guardMembersPage((user, app, admin) => { ...load private content... });
//   </script>
//
// The page's private markup must live inside an element with id="app" that
// is hidden by default (see members.css), so nothing flashes on screen
// before the login check has run.
// -------------------------------------------------------------------------

import { firebaseConfig } from './firebase-config.js';
import { isAdmin, syncServerSession, clearServerSession, MEMBER_HOME } from './session.js';
import { initializeApp } from 'https://www.gstatic.com/firebasejs/10.12.0/firebase-app.js';
import {
  getAuth, onAuthStateChanged, signOut, setPersistence, browserSessionPersistence
} from 'https://www.gstatic.com/firebasejs/10.12.0/firebase-auth.js';

// A single Firebase app/auth instance, shared by whichever page imports this.
export const app = initializeApp(firebaseConfig);
export const auth = getAuth(app);

// Keep the session only until the browser tab is closed (matches index.html).
setPersistence(auth, browserSessionPersistence);

/**
 * Gate a members page behind the Firebase login.
 * @param {(user: object, app: object, admin: boolean) => void} [onReady]
 *        Optional callback run once access is confirmed. Receives the
 *        Firebase user, the initialised app (handy for Firestore) and whether
 *        the user is the admin.
 * @param {{ adminOnly?: boolean }} [options]
 *        adminOnly: only the admin may see this page; members go to Minecraps.
 */
export function guardMembersPage(onReady, { adminOnly = false } = {}) {
  onAuthStateChanged(auth, async (user) => {
    // Gate: no signed-in user -> bounce to the login page. `replace` keeps the
    // protected page out of the browser's back-button history.
    if (!user) {
      window.location.replace('index.html');
      return;
    }

    const admin = await isAdmin(user);
    if (adminOnly && !admin) {
      window.location.replace(MEMBER_HOME);
      return;
    }

    // Make sure the subdomain sign-on cookie exists (e.g. after it expired).
    if (admin) syncServerSession(user);

    document.querySelectorAll('[data-admin-only]').forEach((el) => {
      el.hidden = !admin;
    });

    const welcome = document.getElementById('welcome');
    if (welcome) welcome.textContent = 'Signed in as ' + user.email;

    const appEl = document.getElementById('app');
    if (appEl) appEl.style.display = 'block';

    const signout = document.getElementById('signout');
    if (signout) {
      signout.addEventListener('click', async () => {
        await clearServerSession();
        await signOut(auth);
        window.location.href = 'index.html';
      });
    }

    if (typeof onReady === 'function') onReady(user, app, admin);
  });
}
