// -------------------------------------------------------------------------
// Shared login gate for The Flying Cocker members area
// -------------------------------------------------------------------------
// Every protected members page imports this one module so the login check
// lives in a single place. It:
//   1. Initialises Firebase.
//   2. Redirects to the login page (index.html) if nobody is signed in.
//   3. Reveals the page (#app) once a signed-in user is confirmed.
//   4. Fills in #welcome and wires up the #signout button, if present.
//
// Usage in a members page:
//
//   <script type="module">
//     import { guardMembersPage } from './assets/members-guard.js';
//     guardMembersPage();                    // simple gated page, no extra data
//     // or, to run code once sign-in is confirmed:
//     guardMembersPage((user, app) => { ...load private content... });
//   </script>
//
// The page's private markup must live inside an element with id="app" that
// is hidden by default (see members.css), so nothing flashes on screen
// before the login check has run.
// -------------------------------------------------------------------------

import { firebaseConfig } from './firebase-config.js';
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
 * @param {(user: object, app: object) => void} [onReady]
 *        Optional callback run once a signed-in user is confirmed. Receives
 *        the Firebase user and the initialised app (handy for Firestore).
 */
export function guardMembersPage(onReady) {
  onAuthStateChanged(auth, (user) => {
    // Gate: no signed-in user -> bounce to the login page. `replace` keeps the
    // protected page out of the browser's back-button history.
    if (!user) {
      window.location.replace('index.html');
      return;
    }

    const welcome = document.getElementById('welcome');
    if (welcome) welcome.textContent = 'Signed in as ' + user.email;

    const appEl = document.getElementById('app');
    if (appEl) appEl.style.display = 'block';

    const signout = document.getElementById('signout');
    if (signout) {
      signout.addEventListener('click', async () => {
        await signOut(auth);
        window.location.href = 'index.html';
      });
    }

    if (typeof onReady === 'function') onReady(user, app);
  });
}
