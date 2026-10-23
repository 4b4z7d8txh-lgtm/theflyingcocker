#!/usr/bin/env bash
# -------------------------------------------------------------------------
# Obsidian sync hub + backups for ob.theflyingcocker.co.uk
# -------------------------------------------------------------------------
# Builds on the existing CouchDB container (couchdb-for-obsidian) so the
# Obsidian phone app and the browser Obsidian can sync with the Self-hosted
# LiveSync plugin, then sets up nightly backups. Run as root:
#
#   curl -fsSL https://raw.githubusercontent.com/4b4z7d8txh-lgtm/theflyingcocker/claude/wf-ob-landing-pages-2zcq7f/obsidian-sync-setup.sh -o /root/ob-sync-setup.sh && bash /root/ob-sync-setup.sh
#
# 1. Applies the CouchDB settings LiveSync needs, and creates a dedicated
#    sync user + database (the CouchDB admin account is never used by apps).
# 2. Publishes CouchDB at https://ob.theflyingcocker.co.uk/couchdb/
#    (CouchDB's own username/password; the app can't use the website login).
# 3. Nightly backup at 03:15: CouchDB + plain-Markdown vault, kept 30 days in
#    /root/backups/obsidian, and optionally pushed to a private GitHub repo.
#
# Safe to run again. See OBSIDIAN-SYNC.md for the phone/laptop steps.
# -------------------------------------------------------------------------

set -euo pipefail

COUCH=couchdb-for-obsidian
SYNC_DIR=/root/obsidian-sync
CREDS=$SYNC_DIR/livesync-credentials.txt
SITE=/etc/nginx/sites-available/ob.theflyingcocker.co.uk
PUBLIC_URL=https://ob.theflyingcocker.co.uk/couchdb
DB=obsidian-vault
SYNC_USER=obsidian
GIT_KEY=/root/.ssh/obsidian_backup_ed25519
GIT_CONF=$SYNC_DIR/backup-repo

step() { echo; echo "=== $* ==="; }
fail() { echo; echo "STOPPED: $*"; echo "Send this output to Claude."; exit 1; }
trap 'fail "the command on line $LINENO of the script failed (see the lines above)"' ERR

echo "ob-sync-setup version: 2026-10-23"
[ "$(id -u)" -eq 0 ] || fail "run this as root"

step "1/5 Checks"
docker inspect "$COUCH" >/dev/null 2>&1 || fail "the $COUCH container isn't on this server"
[ "$(docker inspect -f '{{.State.Running}}' "$COUCH")" = true ] || fail "$COUCH isn't running"
[ -e "$SITE" ] || fail "run fc-setup.sh first (ob. site missing)"
grep -q "listen.*443" "$SITE" || fail "ob. has no HTTPS yet - run: bash /root/fc-setup.sh"
apt-get install -y -q git rsync >/dev/null
COUCH_ENV=$(docker inspect -f '{{range .Config.Env}}{{println .}}{{end}}' "$COUCH")
ADMIN_USER=$(printf '%s\n' "$COUCH_ENV" | sed -n 's/^COUCHDB_USER=//p')
ADMIN_PASS=$(printf '%s\n' "$COUCH_ENV" | sed -n 's/^COUCHDB_PASSWORD=//p')
[ -n "$ADMIN_USER" ] && [ -n "$ADMIN_PASS" ] || fail "couldn't read the CouchDB admin login from the container"
CODE=$(curl -s -o /dev/null -w "%{http_code}" -u "$ADMIN_USER:$ADMIN_PASS" http://127.0.0.1:5984/_up || true)
[ "$CODE" = 200 ] || fail "CouchDB isn't answering on 127.0.0.1:5984 (got $CODE)"
echo "CouchDB OK"

step "2/5 CouchDB settings, sync user and database"
if [ -s "$CREDS" ]; then
  SYNC_PASS=$(sed -n 's/^Password: *//p' "$CREDS")
else
  SYNC_PASS=$(python3 -c 'import secrets; print(secrets.token_urlsafe(24))')
fi
ADMIN_USER="$ADMIN_USER" ADMIN_PASS="$ADMIN_PASS" SYNC_USER="$SYNC_USER" SYNC_PASS="$SYNC_PASS" DB="$DB" \
python3 - <<'EOF'
import base64, json, os, urllib.request, urllib.error
BASE = "http://127.0.0.1:5984"
AUTH = "Basic " + base64.b64encode(f"{os.environ['ADMIN_USER']}:{os.environ['ADMIN_PASS']}".encode()).decode()

def call(method, path, body=None, ok=(200, 201, 202)):
    data = None if body is None else json.dumps(body).encode()
    req = urllib.request.Request(BASE + path, data=data, method=method,
                                 headers={"Authorization": AUTH, "Content-Type": "application/json"})
    try:
        with urllib.request.urlopen(req) as r:
            return r.status, json.loads(r.read() or b"null")
    except urllib.error.HTTPError as e:
        if e.code in ok:
            return e.code, None
        raise SystemExit(f"{method} {path} -> {e.code} {e.read()[:200]!r}")

# Settings from the Self-hosted LiveSync documentation.
settings = {
    ("chttpd", "require_valid_user"): "true",
    ("chttpd_auth", "require_valid_user"): "true",
    ("httpd", "WWW-Authenticate"): 'Basic realm="couchdb"',
    ("httpd", "enable_cors"): "true",
    ("chttpd", "enable_cors"): "true",
    ("chttpd", "max_http_request_size"): "4294967296",
    ("couchdb", "max_document_size"): "50000000",
    ("cors", "credentials"): "true",
    ("cors", "origins"): "app://obsidian.md,capacitor://localhost,http://localhost",
}
for (section, key), value in settings.items():
    call("PUT", f"/_node/_local/_config/{section}/{key}", value)

for db in ("_users", "_replicator", os.environ["DB"]):
    call("PUT", "/" + db, ok=(201, 202, 412))   # 412 = already exists

# Dedicated sync user (created, or its password refreshed).
uid = "org.couchdb.user:" + os.environ["SYNC_USER"]
doc = {"name": os.environ["SYNC_USER"], "password": os.environ["SYNC_PASS"], "roles": [], "type": "user"}
try:
    _, existing = call("GET", "/_users/" + uid)
    doc["_rev"] = existing["_rev"]
except SystemExit:
    pass
call("PUT", "/_users/" + uid, doc)

# Only the sync user (and admins) may use the vault database.
call("PUT", f"/{os.environ['DB']}/_security",
     {"admins": {"names": [], "roles": []},
      "members": {"names": [os.environ["SYNC_USER"]], "roles": []}})
print("CouchDB ready for LiveSync")
EOF
umask 077
cat > "$CREDS" <<EOF
Obsidian Self-hosted LiveSync - server details
Server URI: $PUBLIC_URL
Username: $SYNC_USER
Password: $SYNC_PASS
Database name: $DB
EOF
umask 022

step "3/5 Publish CouchDB at $PUBLIC_URL"
cat > /etc/nginx/snippets/fc-couchdb.conf <<'EOF'
# Obsidian LiveSync -> CouchDB. Uses CouchDB's own login (apps can't use the
# website sign-in cookie), so the members gate is switched off here.
location /couchdb/ {
    auth_request off;
    proxy_pass http://127.0.0.1:5984/;
    proxy_redirect off;
    proxy_buffering off;
    proxy_http_version 1.1;
    proxy_set_header Host $host;
    proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
    proxy_set_header X-Forwarded-Proto $scheme;
    proxy_read_timeout 3600s;
    client_max_body_size 100m;
}
EOF
cp "$SITE" /root/nginx-ob-backup.conf
python3 - "$SITE" <<'EOF' || fail "could not add /couchdb/ to the ob. site"
# Add the include inside the HTTPS server block for ob.theflyingcocker.co.uk.
import re, sys
p = sys.argv[1]; lines = open(p).read().split('\n')
if any('fc-couchdb.conf' in l and not l.strip().startswith('#') for l in lines):
    print('already published'); sys.exit()
depth, block, target = 0, None, None
for n, l in enumerate(lines):
    code = l.split('#', 1)[0]
    if depth == 0 and re.match(r'\s*server\s*\{', code):
        block = {'listen': None, 'ours': False}
    if block is not None:
        if block['listen'] is None and re.match(r'\s*listen\s+(\[::\]:)?443\b', code):
            block['listen'] = n
        if re.search(r'server_name\s[^;]*ob\.theflyingcocker', code):
            block['ours'] = True
    depth += code.count('{') - code.count('}')
    if depth == 0 and block is not None:
        if block['ours'] and block['listen'] is not None:
            target = block['listen']; break
        block = None
if target is None:
    sys.exit('no HTTPS server block for ob.theflyingcocker.co.uk in ' + p)
lines.insert(target + 1, '    include snippets/fc-couchdb.conf;')
open(p, 'w').write('\n'.join(lines))
print('published')
EOF
if ! nginx -t; then
  cp /root/nginx-ob-backup.conf "$SITE"
  fail "Nginx check failed - ob. config restored, nothing broken"
fi
systemctl reload nginx
sleep 1
CODE=$(curl -s -o /dev/null -w "%{http_code}" -u "$SYNC_USER:$SYNC_PASS" "$PUBLIC_URL/$DB" || true)
[ "$CODE" = 200 ] || fail "the sync address answered $CODE instead of 200"
CODE=$(curl -s -o /dev/null -w "%{http_code}" "$PUBLIC_URL/$DB" || true)
[ "$CODE" = 401 ] || fail "the sync address isn't asking for a password (got $CODE)"
echo "sync address works and is password-protected"

step "4/5 Nightly backups"
cat > /usr/local/bin/obsidian-backup.sh <<'EOF'
#!/usr/bin/env bash
# Nightly Obsidian backup (installed by obsidian-sync-setup.sh).
set -euo pipefail
DEST=/root/backups/obsidian
D=$(date +%F)
mkdir -p "$DEST"
umask 077

# 1. The CouchDB sync database (everything LiveSync holds).
# CouchDB's files are append-only, so a copy taken while it runs is usable;
# tar exit code 1 only means "a file changed while being read".
tar czf "$DEST/couchdb-$D.tgz" --warning=no-file-changed -C /root/obsidian-sync couchdb-data || [ $? -eq 1 ]

# 2. Plain-Markdown copy of each vault opened in the browser Obsidian.
VAULTS=()
while IFS= read -r -d '' dot; do VAULTS+=("$(dirname "$dot")"); done \
  < <(find /opt/obsidian/config -maxdepth 4 -type d -name .obsidian -print0 2>/dev/null || true)
for vault in "${VAULTS[@]}"; do
  name=$(basename "$vault")
  tar czf "$DEST/vault-${name// /_}-$D.tgz" \
    --exclude='.obsidian/plugins/obsidian-livesync' -C "$(dirname "$vault")" "$name"
done

# Keep 30 days.
find "$DEST" -name '*.tgz' -mtime +30 -delete

# 3. Off-server copy: the Markdown pushed to a private GitHub repo, if set up.
if [ -s /root/obsidian-sync/backup-repo ]; then
  REPO_URL=$(cat /root/obsidian-sync/backup-repo)
  WORK=/root/obsidian-sync/git-backup
  export GIT_SSH_COMMAND="ssh -i /root/.ssh/obsidian_backup_ed25519 -o IdentitiesOnly=yes -o StrictHostKeyChecking=accept-new"
  if [ ! -d "$WORK/.git" ]; then
    rm -rf "$WORK"
    git clone -q "$REPO_URL" "$WORK" 2>/dev/null || { mkdir -p "$WORK"; git -C "$WORK" init -q -b main; git -C "$WORK" remote add origin "$REPO_URL"; }
  fi
  for vault in "${VAULTS[@]}"; do
    # Leave out LiveSync's settings (they hold the sync password/passphrase)
    # and per-device window layout.
    rsync -a --delete --exclude='.obsidian/plugins/obsidian-livesync/' \
      --exclude='.obsidian/workspace*.json' --exclude='.trash/' "$vault/" "$WORK/$(basename "$vault")/"
  done
  cd "$WORK"
  git add -A
  if ! git diff --cached --quiet; then
    git -c user.name="Obsidian backup" -c user.email="backup@theflyingcocker.co.uk" commit -q -m "Backup $D"
  fi
  git rev-parse -q --verify HEAD >/dev/null && git push -q origin HEAD:main
fi
echo "$(date '+%F %T') backup OK"
EOF
chmod 700 /usr/local/bin/obsidian-backup.sh
echo '15 3 * * * root /usr/local/bin/obsidian-backup.sh >> /var/log/obsidian-backup.log 2>&1' > /etc/cron.d/obsidian-backup
chmod 644 /etc/cron.d/obsidian-backup
echo "nightly backup scheduled for 03:15 (kept 30 days in /root/backups/obsidian)"

step "5/5 Off-server copy on GitHub (optional)"
if [ -s "$GIT_CONF" ]; then
  echo "already set up: $(cat "$GIT_CONF")"
else
  mkdir -p /root/.ssh && chmod 700 /root/.ssh
  [ -s "$GIT_KEY" ] || ssh-keygen -q -t ed25519 -N "" -C "obsidian-backup@theflyingcocker" -f "$GIT_KEY"
  echo "1. On GitHub, create a new PRIVATE repository, e.g. 'obsidian-vault' (leave it empty)."
  echo "2. In that repo: Settings > Deploy keys > Add deploy key. Title: VPS backup."
  echo "   Paste this key and TICK 'Allow write access':"
  echo
  cat "$GIT_KEY.pub"
  echo
  echo "3. Then type the repo as owner/name (e.g. 4b4z7d8txh-lgtm/obsidian-vault)"
  echo "   and press Enter - or just press Enter to skip this for now:"
  IFS= read -r GH_REPO || GH_REPO=""
  GH_REPO=$(printf '%s' "$GH_REPO" | tr -d '[:space:]')
  if [ -n "$GH_REPO" ]; then
    URL="git@github.com:${GH_REPO%.git}.git"
    if GIT_SSH_COMMAND="ssh -i $GIT_KEY -o IdentitiesOnly=yes -o StrictHostKeyChecking=accept-new" git ls-remote "$URL" >/dev/null 2>&1; then
      echo "$URL" > "$GIT_CONF"
      echo "GitHub repo connected: $URL"
    else
      echo "Couldn't reach $URL with that key - check the name and that the deploy key"
      echo "has write access, then run this script again. (Everything else is done.)"
    fi
  else
    echo "Skipped. Run this script again any time to add it."
  fi
fi
/usr/local/bin/obsidian-backup.sh || echo "(first backup run had a problem - see above)"

echo
echo "================================================================"
echo " ALL DONE. Enter these in the LiveSync plugin (phone first):"
echo
sed 's/^/   /' "$CREDS"
echo
echo " Saved on the server - show them again any time with:"
echo "   cat $CREDS"
echo "================================================================"
