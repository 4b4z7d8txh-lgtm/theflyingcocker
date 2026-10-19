// Make (or unmake) a Firebase user the site administrator.
//
//   node set-admin.js you@example.com           -> grant admin
//   node set-admin.js you@example.com --remove  -> remove admin
//
// Admins can open every subdomain (wf., ob.) and every members page. Everyone
// else only gets Minecraps. The change applies the next time that person
// signs in, so sign out and back in afterwards.

'use strict';

const admin = require('firebase-admin');

const [email, flag] = process.argv.slice(2);
if (!email) {
  console.error('Usage: node set-admin.js <email> [--remove]');
  process.exit(1);
}

admin.initializeApp({ credential: admin.credential.applicationDefault() });

(async () => {
  const user = await admin.auth().getUserByEmail(email);
  const claims = { ...(user.customClaims || {}) };
  if (flag === '--remove') delete claims.admin;
  else claims.admin = true;
  await admin.auth().setCustomUserClaims(user.uid, claims);
  console.log(`${email}: admin = ${claims.admin === true}. Sign out and back in to apply.`);
})().catch((err) => {
  console.error(err.message);
  process.exit(1);
});
