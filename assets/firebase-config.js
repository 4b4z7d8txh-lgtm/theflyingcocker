// -------------------------------------------------------------------------
// Firebase configuration for The Flying Cocker
// -------------------------------------------------------------------------
// Paste the config object from your Firebase project here (SETUP.md, step 3).
//
// NOTE: These values are NOT secret. Firebase web config is *designed* to be
// public and safe to commit. Your real security comes from two things:
//   1. Only YOU can create accounts (sign-up is disabled in the console).
//   2. The Firestore rules in `firestore.rules`, which release private
//      content only to a signed-in, approved user.
// -------------------------------------------------------------------------

export const firebaseConfig = {
  apiKey: "PASTE_apiKey_HERE",
  authDomain: "PASTE_authDomain_HERE",
  projectId: "PASTE_projectId_HERE",
  storageBucket: "PASTE_storageBucket_HERE",
  messagingSenderId: "PASTE_messagingSenderId_HERE",
  appId: "PASTE_appId_HERE"
};
