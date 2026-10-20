// -------------------------------------------------------------------------
// Single sign-on helpers shared by the login page and members pages
// -------------------------------------------------------------------------
// - syncServerSession(user): hands the Firebase login to the sign-on helper on
//   the VPS (auth-service/), which sets one cookie valid on every
//   *.theflyingcocker.co.uk subdomain. That's what lets members open
//   wf. and ob. without being asked to sign in again.
// - clearServerSession(): removes that cookie on Sign out.
//
// The sign-on helper only exists on the VPS. Anywhere else (e.g. a local
// preview) these calls fail quietly and the site works as before.
// -------------------------------------------------------------------------

export const HOME = 'members.html';

// Subdomains a member can be sent back to after signing in.
const NEXT_HOST = /^https:\/\/[a-z0-9-]+\.theflyingcocker\.co\.uk(\/|$)/;

export async function syncServerSession(user) {
  try {
    await fetch('/auth/session', {
      method: 'POST',
      credentials: 'same-origin',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ idToken: await user.getIdToken() }),
    });
  } catch (e) {
    // Sign-on helper not reachable: subdomains will ask again, nothing else breaks.
  }
}

export async function clearServerSession() {
  try {
    await fetch('/auth/logout', { method: 'POST', credentials: 'same-origin' });
  } catch (e) { /* see above */ }
}

/** A safe ?next= target on one of our subdomains, or '' if none/invalid. */
export function nextUrl() {
  const next = new URLSearchParams(window.location.search).get('next') || '';
  return NEXT_HOST.test(next) ? next : '';
}
