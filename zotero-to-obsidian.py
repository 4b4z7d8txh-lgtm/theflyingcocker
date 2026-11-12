#!/usr/bin/env python3
# -------------------------------------------------------------------------
# Zotero -> Obsidian: notes and highlights from zotero.org into the vault
# -------------------------------------------------------------------------
# Installed by zotero-obsidian-setup.sh as /usr/local/bin/zotero-to-obsidian
# and run every 15 minutes by cron. See ZOTERO-OBSIDIAN.md.
#
# What it does:
#   - asks the Zotero web API (read-only key) which notes and annotations
#     (highlights) changed since the last run;
#   - writes one Markdown file per book/article into <vault>/Zotero/, and one
#     file per standalone note into <vault>/Zotero/Notes/;
#   - the browser Obsidian on ob. sees the file and LiveSync sends it to the
#     phone.
#
# Each file has a line "<!-- zotero:end ... -->". Everything ABOVE it is
# rewritten from Zotero; everything BELOW it (the "My thoughts" part) is
# never touched. One-way only: nothing is ever sent back to Zotero.
#
# Usage:
#   zotero-to-obsidian            normal run (only what changed)
#   zotero-to-obsidian --full     rebuild every file (your thoughts are kept)
#   zotero-to-obsidian --setup VAULT_PATH
#                                 check the key (from $ZO_KEY, or the saved one)
#                                 and save the settings
#
# Only the Python standard library is used. Settings and state live in
# /opt/zotero-obsidian (config.json holds the key: root only).
# -------------------------------------------------------------------------

import json
import os
import re
import sys
import time
import urllib.error
import urllib.parse
import urllib.request
from html.parser import HTMLParser

VERSION = "2026-11-12"
CONF_DIR = os.environ.get("ZO_CONF_DIR", "/opt/zotero-obsidian")
CONF_FILE = os.path.join(CONF_DIR, "config.json")
STATE_FILE = os.path.join(CONF_DIR, "state.json")
API = os.environ.get("ZOTERO_API", "https://api.zotero.org").rstrip("/")
FOLDER = "Zotero"
NOTES_FOLDER = "Notes"
END_MARK = "<!-- zotero:end · everything above this line is rewritten from Zotero. Write your own notes below it. -->"
END_RE = re.compile(r"^<!-- zotero:end.*?-->[ \t]*$", re.M)
USER_PART = "\n\n## My thoughts\n\n"


class Fatal(Exception):
    pass


def log(msg):
    print(time.strftime("%Y-%m-%d %H:%M:%S"), msg, flush=True)


# ---------------------------------------------------------------- web API --

class Zotero:
    def __init__(self, key, prefix=""):
        self.key = key
        self.prefix = prefix          # e.g. "/users/123456"
        self.requests = 0

    def get(self, path, params=None, absolute=False):
        url = API + ("" if absolute else self.prefix) + path
        if params:
            url += "?" + urllib.parse.urlencode(params)
        last = ""
        for attempt in range(6):
            req = urllib.request.Request(url, headers={
                "Zotero-API-Version": "3",
                "Zotero-API-Key": self.key,
                "User-Agent": "zotero-to-obsidian/" + VERSION,
            })
            try:
                self.requests += 1
                with urllib.request.urlopen(req, timeout=60) as r:
                    body = r.read()
                    headers = r.headers
                backoff = headers.get("Backoff")
                if backoff and backoff.isdigit():
                    time.sleep(min(int(backoff), 600))
                return json.loads(body.decode("utf-8") or "null"), headers
            except urllib.error.HTTPError as e:
                if e.code in (429, 500, 502, 503, 504):
                    wait = e.headers.get("Retry-After")
                    wait = int(wait) if wait and wait.isdigit() else 5 * 2 ** attempt
                    last = "HTTP %d" % e.code
                    time.sleep(min(wait, 600))
                    continue
                if e.code == 403:
                    raise Fatal("zotero.org refused the key (403). Make a new key with "
                                "'Allow library access' and 'Allow notes access' ticked, "
                                "then run the setup line again.")
                if e.code == 404:
                    return None, e.headers
                raise Fatal("zotero.org answered HTTP %d for %s" % (e.code, path))
            except (urllib.error.URLError, TimeoutError, OSError) as e:
                last = str(e)
                time.sleep(5 * 2 ** attempt)
        raise Fatal("couldn't reach zotero.org (%s). It will try again next run." % last)

    def get_all(self, path, params=None):
        """All pages of a list. Returns (items, headers of the first page)."""
        out, first, start = [], None, 0
        while True:
            p = dict(params or {}, limit=100, start=start)
            data, headers = self.get(path, p)
            if first is None:
                first = headers
            if not data:
                break
            out += data
            start += len(data)
            total = headers.get("Total-Results")
            if total is None or start >= int(total):
                break
        return out, first


# ------------------------------------------------------ HTML -> Markdown --

class _MD(HTMLParser):
    """Small HTML-to-Markdown converter for Zotero notes."""

    BLOCKS = {"p", "div", "section", "article", "table", "figure"}

    def __init__(self, demote):
        super().__init__(convert_charrefs=True)
        self.demote = demote
        self.stack = [[]]       # output buffers (blockquotes get their own)
        self.lists = []         # [kind, counter]
        self.links = []
        self.pre = 0

    def w(self, s):
        self.stack[-1].append(s)

    def handle_starttag(self, tag, attrs):
        a = dict(attrs)
        if tag in self.BLOCKS:
            self.w("\n\n")
        elif re.fullmatch(r"h[1-6]", tag):
            self.w("\n\n" + "#" * min(6, int(tag[1]) + self.demote) + " ")
        elif tag == "br":
            self.w("  \n")
        elif tag in ("strong", "b"):
            self.w("**")
        elif tag in ("em", "i"):
            self.w("*")
        elif tag in ("s", "del", "strike"):
            self.w("~~")
        elif tag == "code" and not self.pre:
            self.w("`")
        elif tag == "pre":
            self.pre += 1
            self.w("\n\n```\n")
        elif tag == "blockquote":
            self.stack.append([])
        elif tag in ("ul", "ol"):
            self.lists.append([tag, 0])
            if len(self.lists) == 1:
                self.w("\n")
        elif tag == "li":
            depth = max(len(self.lists), 1)
            kind = self.lists[-1] if self.lists else ["ul", 0]
            kind[1] += 1
            bullet = "%d. " % kind[1] if kind[0] == "ol" else "- "
            self.w("\n" + "    " * (depth - 1) + bullet)
        elif tag == "a":
            self.links.append(a.get("href") or "")
            self.w("[")
        elif tag == "img":
            self.w("*(image: open the note in Zotero to see it)*")
        elif tag == "hr":
            self.w("\n\n---\n\n")
        elif tag == "tr":
            self.w("\n")

    def handle_endtag(self, tag):
        if tag in self.BLOCKS or re.fullmatch(r"h[1-6]", tag):
            self.w("\n\n")
        elif tag in ("strong", "b"):
            self.w("**")
        elif tag in ("em", "i"):
            self.w("*")
        elif tag in ("s", "del", "strike"):
            self.w("~~")
        elif tag == "code" and not self.pre:
            self.w("`")
        elif tag == "pre":
            self.pre = max(0, self.pre - 1)
            self.w("\n```\n\n")
        elif tag == "blockquote" and len(self.stack) > 1:
            inner = _tidy("".join(self.stack.pop()))
            self.w("\n\n" + "\n".join(("> " + l).rstrip() for l in inner.split("\n")) + "\n\n")
        elif tag in ("ul", "ol"):
            if self.lists:
                self.lists.pop()
            if not self.lists:
                self.w("\n\n")
        elif tag == "a":
            href = self.links.pop() if self.links else ""
            self.w("](%s)" % href if href and not href.startswith("#") else "]")
        elif tag in ("td", "th"):
            self.w(" | ")

    def handle_data(self, data):
        if self.pre:
            self.w(data)
        else:
            self.w(re.sub(r"\s+", " ", data))

    def result(self):
        while len(self.stack) > 1:
            self.handle_endtag("blockquote")
        return _tidy("".join(self.stack[0]))


def _tidy(s):
    lines = [l.rstrip() if not l.endswith("  ") else l for l in s.split("\n")]
    out = "\n".join(l.lstrip() if not re.match(r"^\s+(- |\d+\. )", l) else l for l in lines)
    out = re.sub(r"\[\]\([^)]*\)", "", out)          # empty links
    out = re.sub(r"\n{3,}", "\n\n", out)
    return out.strip()


def html_to_md(html_text, demote=2):
    p = _MD(demote)
    p.feed(html_text or "")
    p.close()
    return p.result()


# --------------------------------------------------------------- helpers --

def safe_name(s, limit=110):
    s = re.sub(r'[\\/:*?"<>|#^\[\]\r\n\t]', " ", s or "")
    s = re.sub(r"\s+", " ", s).strip().strip(".").strip()
    if len(s) > limit:
        s = s[:limit].rsplit(" ", 1)[0].rstrip(" .,;–-")
    return s or "Untitled"


def creator_name(c):
    return (c.get("lastName") or c.get("name") or "").strip()


def authors_of(d):
    cs = d.get("creators") or []
    main = [c for c in cs if c.get("creatorType") == "author"] or cs
    return main


def short_authors(d):
    names = [n for n in (creator_name(c) for c in authors_of(d)) if n]
    if not names:
        return ""
    if len(names) == 1:
        return names[0]
    if len(names) == 2:
        return names[0] + " & " + names[1]
    return names[0] + " et al"


def full_author(c):
    if c.get("name"):
        return c["name"].strip()
    return " ".join(x for x in (c.get("firstName", "").strip(), c.get("lastName", "").strip()) if x)


def year_of(d):
    m = re.search(r"\b(\d{4})\b", d.get("date") or "")
    return m.group(1) if m else ""


def yaml_str(s):
    return json.dumps(s, ensure_ascii=False)


def tag_text(tags):
    out = []
    for t in tags or []:
        name = re.sub(r"[^\w/-]+", "-", (t.get("tag") or "").strip()).strip("-")
        if name and not name.isdigit():
            out.append("#" + name)
    return " ".join(out)


def note_title(html_text):
    md = html_to_md(html_text, demote=0)
    for line in md.split("\n"):
        line = re.sub(r"^[#>\-*\s\d.]+", "", line).replace("**", "").replace("*", "").strip()
        if line:
            return line
    return "Untitled note"


# -------------------------------------------------------------- rendering --

def render_annotation(a):
    d = a["data"]
    kind = d.get("annotationType")
    page = (d.get("annotationPageLabel") or "").strip()
    where = ("p. " + page) if page else ""
    text = (d.get("annotationText") or "").strip()
    comment = html_to_md(d.get("annotationComment") or "", demote=3) if d.get("annotationComment") else ""
    tags = tag_text(d.get("tags"))
    parts = []
    if kind in ("highlight", "underline") and text:
        quote = "\n".join(("> " + l).rstrip() for l in text.split("\n"))
        if where:
            quote += "\n> — " + where
        parts.append(quote)
    elif kind in ("image", "ink"):
        parts.append("*Drawing or image%s (open it in Zotero to see it)*" % (" on " + where if where else ""))
    elif kind in ("note", "text"):
        parts.append("**Note%s:**" % (" (" + where + ")" if where else ""))
    if comment:
        parts.append(comment)
    if tags:
        parts.append(tags)
    return "\n\n".join(parts)


def render_book(d, username, annotation_groups, notes):
    title = (d.get("title") or "").strip() or "Untitled"
    authors = [n for n in (full_author(c) for c in authors_of(d)) if n]
    year = year_of(d)
    link = "https://www.zotero.org/%s/items/%s" % (username, d["key"]) if username else ""
    fm = ["---", "title: " + yaml_str(title)]
    if authors:
        fm.append("authors:")
        fm += ["  - " + yaml_str(a) for a in authors]
    if year:
        fm.append("year: " + yaml_str(year))
    fm.append("type: " + yaml_str(d.get("itemType", "")))
    for field in ("publicationTitle", "publisher", "DOI", "ISBN", "url"):
        if (d.get(field) or "").strip():
            fm.append(field.lower() + ": " + yaml_str(d[field].strip()))
    fm.append("zotero_key: " + yaml_str(d["key"]))
    if link:
        fm.append("zotero_link: " + yaml_str(link))
    fm += ["tags:", "  - zotero", "---"]

    body = ["# " + title]
    info = " · ".join(x for x in (", ".join(authors), year) if x)
    if link:
        info = (info + " · " if info else "") + "[Open in Zotero](%s)" % link
    if info:
        body.append(info)

    if annotation_groups:
        body.append("## Highlights")
        many = len(annotation_groups) > 1
        for att_title, anns in annotation_groups:
            if many:
                body.append("### " + (att_title or "Attachment"))
            for a in anns:
                r = render_annotation(a)
                if r:
                    body.append(r)
    if notes:
        body.append("## Notes")
        for i, n in enumerate(notes):
            if i:
                body.append("---")
            body.append(html_to_md(n["data"].get("note", ""), demote=2) or "*(empty note)*")
    if not annotation_groups and not notes:
        body.append("*No notes or highlights in Zotero right now.*")
    return "\n".join(fm) + "\n\n" + "\n\n".join(body) + "\n\n" + END_MARK


def render_standalone(d, username):
    title = note_title(d.get("note", ""))
    link = "https://www.zotero.org/%s/items/%s" % (username, d["key"]) if username else ""
    fm = ["---", "title: " + yaml_str(title), "zotero_key: " + yaml_str(d["key"])]
    if link:
        fm.append("zotero_link: " + yaml_str(link))
    fm += ["tags:", "  - zotero", "  - zotero-note", "---"]
    body = html_to_md(d.get("note", ""), demote=0) or "*(empty note)*"
    if link:
        body += "\n\n[Open in Zotero](%s)" % link
    return "\n".join(fm) + "\n\n" + body + "\n\n" + END_MARK


# ---------------------------------------------------------------- writing --

class Vault:
    def __init__(self, path):
        self.path = path
        st = os.stat(path)
        self.uid, self.gid = st.st_uid, st.st_gid
        self.written = 0
        self.renamed = 0

    def _own(self, p):
        try:
            os.chown(p, self.uid, self.gid)
        except PermissionError:
            pass

    def _mkdirs(self, rel_dir):
        cur = self.path
        for part in rel_dir.split("/"):
            cur = os.path.join(cur, part)
            if not os.path.isdir(cur):
                os.mkdir(cur)
                self._own(cur)

    def write(self, rel, managed, old_rel=None):
        """Write the managed part of a note, keeping what's below the end mark."""
        full = os.path.join(self.path, rel)
        if old_rel and old_rel != rel:
            old_full = os.path.join(self.path, old_rel)
            if os.path.exists(old_full) and not os.path.exists(full):
                self._mkdirs(os.path.dirname(rel))
                os.rename(old_full, full)
                self.renamed += 1
                log("renamed: %s -> %s" % (old_rel, rel))
        user = USER_PART
        old = None
        if os.path.exists(full):
            with open(full, encoding="utf-8") as f:
                old = f.read()
            m = END_RE.search(old)
            if not m:
                log("SKIPPED (the zotero:end line was removed, so I won't overwrite it): " + rel)
                return
            user = old[m.end():]
        new = managed + user
        if new == old:
            return
        self._mkdirs(os.path.dirname(rel))
        tmp = full + ".zo-tmp"
        with open(tmp, "w", encoding="utf-8") as f:
            f.write(new)
        self._own(tmp)
        os.replace(tmp, full)
        self.written += 1
        log(("updated: " if old is not None else "new: ") + rel)


# ------------------------------------------------------------------- sync --

def load_json(path, default):
    try:
        with open(path, encoding="utf-8") as f:
            return json.load(f)
    except FileNotFoundError:
        return default


def save_json(path, data, mode=0o600):
    tmp = path + ".tmp"
    with open(tmp, "w", encoding="utf-8") as f:
        json.dump(data, f, indent=1, sort_keys=True)
    os.chmod(tmp, mode)
    os.replace(tmp, path)


def is_live(item):
    return item is not None and not item.get("data", {}).get("deleted")


class Sync:
    def __init__(self, conf, state):
        self.conf = conf
        self.state = state
        for k in ("parents", "files", "atts"):
            state.setdefault(k, {})
        self.z = Zotero(conf["api_key"], "/users/%s" % conf["user_id"])
        self.vault = Vault(conf["vault"])
        self.username = conf.get("username", "")

    def top_of(self, d):
        """The book/article an annotation or note belongs to."""
        parent = d.get("parentItem")
        if not parent:
            return d["key"]
        if d.get("itemType") != "annotation":
            return parent
        atts = self.state["atts"]
        if parent not in atts:
            item, _ = self.z.get("/items/" + parent)
            atts[parent] = (item or {}).get("data", {}).get("parentItem") or parent
        return atts[parent]

    def unique(self, key, rel):
        taken = {v: k for k, v in self.state["files"].items()}
        if rel in taken and taken[rel] != key:
            base, ext = os.path.splitext(rel)
            rel = "%s (%s)%s" % (base, key, ext)
        return rel

    def build_book(self, key):
        item, _ = self.z.get("/items/" + key)
        if not is_live(item):
            return
        d = item["data"]
        if d.get("itemType") in ("note", "annotation"):
            return
        children, _ = self.z.get_all("/items/%s/children" % key)
        children = [c for c in children if is_live(c)]
        notes = [c for c in children if c["data"].get("itemType") == "note"]
        groups = []
        direct = [c for c in children if c["data"].get("itemType") == "annotation"]
        if direct:
            groups.append((d.get("title", ""), direct))
        for att in (c for c in children if c["data"].get("itemType") == "attachment"):
            self.state["atts"][att["key"]] = key
            anns, _ = self.z.get_all("/items/%s/children" % att["key"])
            anns = [a for a in anns if is_live(a) and a["data"].get("itemType") == "annotation"]
            if anns:
                groups.append((att["data"].get("title", ""), anns))
        for _, anns in groups:
            anns.sort(key=lambda a: a["data"].get("annotationSortIndex") or "")
            for a in anns:
                self.state["parents"][a["key"]] = key
        notes.sort(key=lambda n: n["data"].get("dateAdded") or "")
        for n in notes:
            self.state["parents"][n["key"]] = key

        old_rel = self.state["files"].get(key)
        if not groups and not notes and not old_rel:
            return
        name = " ".join(x for x in (short_authors(d), year_of(d)) if x)
        name = (name + " – " if name else "") + (d.get("title") or "Untitled")
        rel = self.unique(key, "%s/%s.md" % (FOLDER, safe_name(name)))
        self.vault.write(rel, render_book(d, self.username, groups, notes), old_rel)
        self.state["files"][key] = rel

    def build_standalone(self, item):
        d = item["data"]
        old_rel = self.state["files"].get(d["key"])
        rel = self.unique(d["key"], "%s/%s/%s.md" % (FOLDER, NOTES_FOLDER, safe_name(note_title(d.get("note", "")))))
        self.vault.write(rel, render_standalone(d, self.username), old_rel)
        self.state["files"][d["key"]] = rel

    def run(self, full=False):
        since = 0 if full else int(self.state.get("version", 0))
        changed, headers = self.z.get_all("/items", {
            "since": since, "itemType": "note || annotation", "includeTrashed": 1})
        if headers is None or headers.get("Last-Modified-Version") is None:
            raise Fatal("zotero.org didn't say which version the library is at")
        new_version = int(headers["Last-Modified-Version"])

        books, standalone = set(), []
        for it in changed:
            d = it["data"]
            if d.get("itemType") == "note" and not d.get("parentItem"):
                if is_live(it):
                    standalone.append(it)
                continue
            top = self.top_of(d)
            self.state["parents"][d["key"]] = top
            books.add(top)

        if since:
            # A book's title/authors changed: refresh its file too.
            tops, _ = self.z.get("/items/top", {"since": since, "format": "versions", "includeTrashed": 1})
            books |= {k for k in (tops or {}) if k in self.state["files"]}
            # Notes/highlights deleted for good (emptied from the trash).
            deleted, _ = self.z.get("/deleted", {"since": since})
            for k in (deleted or {}).get("items", []):
                if k in self.state["parents"]:
                    books.add(self.state["parents"].pop(k))

        for key in sorted(books):
            self.build_book(key)
        for it in standalone:
            self.build_standalone(it)

        self.state["version"] = new_version
        self.state["last_run"] = time.strftime("%Y-%m-%d %H:%M:%S")
        log("done: %d changed in Zotero, %d file(s) written, %d renamed, library version %d (%d requests)"
            % (len(changed), self.vault.written, self.vault.renamed, new_version, self.z.requests))


# ------------------------------------------------------------------- main --

def setup(vault):
    conf = load_json(CONF_FILE, {})
    key = os.environ.get("ZO_KEY", "").strip() or conf.get("api_key", "")
    if not key:
        raise Fatal("no Zotero key given")
    if not re.fullmatch(r"[A-Za-z0-9]{20,40}", key):
        raise Fatal("that doesn't look like a Zotero key (it should be about 24 letters and numbers, no spaces)")
    info, _ = Zotero(key).get("/keys/current", absolute=True)
    if not info or "userID" not in info:
        raise Fatal("zotero.org doesn't know this key. Copy it again from zotero.org/settings/keys")
    access = (info.get("access") or {}).get("user") or {}
    if not access.get("library"):
        raise Fatal("this key can't read your library: edit it on zotero.org and tick 'Allow library access'")
    if not access.get("notes"):
        raise Fatal("this key can't read notes: edit it on zotero.org and tick 'Allow notes access'")
    if access.get("write"):
        log("note: this key also allows writing. Not needed - you could untick 'Allow write access' on zotero.org")
    if not os.path.isdir(vault):
        raise Fatal("vault folder not found: " + vault)
    if conf.get("vault") and conf["vault"] != vault:
        save_json(STATE_FILE, {})          # new vault: start again from scratch
    conf.update(api_key=key, user_id=info["userID"], username=info.get("username", ""), vault=vault)
    os.makedirs(CONF_DIR, mode=0o700, exist_ok=True)
    save_json(CONF_FILE, conf)
    log("key OK for zotero.org user '%s'; notes go to %s/%s" % (conf["username"], vault, FOLDER))


def main(argv):
    try:
        if argv[:1] == ["--setup"] and len(argv) == 2:
            setup(argv[1])
            return 0
        if argv and argv != ["--full"]:
            print(__doc__ or "usage: zotero-to-obsidian [--full | --setup VAULT]")
            return 2
        conf = load_json(CONF_FILE, None)
        if not conf:
            raise Fatal("not set up yet: run the setup line from ZOTERO-OBSIDIAN.md")
        state = load_json(STATE_FILE, {})
        sync = Sync(conf, state)
        try:
            sync.run(full=argv == ["--full"])
        finally:
            save_json(STATE_FILE, state)   # keeps what was learned, version only moves on success
        return 0
    except Fatal as e:
        log("PROBLEM: %s" % e)
        return 1


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
