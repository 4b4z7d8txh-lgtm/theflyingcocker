/*
 * Simple client-side login gate for The Flying Cocker.
 *
 * -------------------------------------------------------------------------
 * HOW TO ADD / CHANGE APPROVED USERS
 * -------------------------------------------------------------------------
 * Edit the APPROVED_USERS list below. Each entry is a username and password.
 * Example:
 *     { username: 'jane',  password: 'letmein-2026' },
 *
 * -------------------------------------------------------------------------
 * IMPORTANT SECURITY NOTE
 * -------------------------------------------------------------------------
 * This runs entirely in the visitor's browser, so the passwords below are
 * visible to anyone who views the page source. That is fine for gating a
 * members area (keeping casual visitors out, giving members a private space)
 * but it is NOT real protection for sensitive data. If you need genuine
 * security, the login must be checked on a server instead. See README.md.
 */
(function (global) {
  'use strict';

  var APPROVED_USERS = [
    // Change these before going live. Add as many as you like.
    { username: 'admin',  password: 'change-me-please' },
    { username: 'member', password: 'flying-cocker-2026' }
  ];

  var SESSION_KEY = 'tfc_user';

  var Auth = {
    // Returns the username string on success, or null on failure.
    signIn: function (username, password) {
      for (var i = 0; i < APPROVED_USERS.length; i++) {
        var u = APPROVED_USERS[i];
        if (u.username === username && u.password === password) {
          try {
            sessionStorage.setItem(SESSION_KEY, username);
          } catch (e) { /* storage may be blocked; sign-in still redirects */ }
          return username;
        }
      }
      return null;
    },

    // Returns the signed-in username, or null if nobody is signed in.
    currentUser: function () {
      try {
        return sessionStorage.getItem(SESSION_KEY);
      } catch (e) {
        return null;
      }
    },

    signOut: function () {
      try {
        sessionStorage.removeItem(SESSION_KEY);
      } catch (e) { /* no-op */ }
    }
  };

  global.Auth = Auth;
})(window);
