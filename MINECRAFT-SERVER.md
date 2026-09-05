# Minecraft (Bedrock) server runbook — The Flying Cocker

How to run the family **Minecraft: Bedrock Edition** server on the same
Fasthosts VPS that hosts the website. The website (Nginx on ports 80/443) and
the game server (UDP port 19132) don't clash — they run side by side.

> Plain-language summary: we install Mojang's official Bedrock server program on
> the Linux server, tell it who's allowed in (an "allow-list" of gamertags), and
> set it to run 24/7 and restart itself if it crashes or the server reboots. The
> kids then add `mc.theflyingcocker.co.uk` in their game and join.

This pairs with the members page **`minecraps.html`**, which shows the kids the
address, the join steps and whether the server is online.

- **Who this is for:** Bedrock players — Xbox, PlayStation, Nintendo Switch,
  iPhone/iPad, Android, and the “Minecraft” app on Windows 10/11.
  (Java Edition on PC cannot join a Bedrock server.)
- **Connect address:** `mc.theflyingcocker.co.uk`  **Port:** `19132`

Run everything below **on the VPS, connected as `root`** (`ssh root@YOUR_SERVER_IP`),
unless a step says otherwise.

---

## 0. Will it fit? (quick sizing note)

Bedrock is light. For a handful of family players you want roughly:

| Players | RAM to spare | Disk |
|--------|--------------|------|
| 2–5    | ~1 GB free   | ~2 GB (grows with the world) |

Check what the VPS has spare:

```bash
free -h        # look at the "available" column
df -h /        # free disk on the root filesystem
```

If “available” RAM is comfortably above ~1 GB you're fine. If it's tight, the
server will still run but may lag with several players at once.

---

## 1. DNS — point `mc.` at the server

Add an **A record** so `mc.theflyingcocker.co.uk` resolves to the VPS. Do this at
wherever the domain's DNS is managed (the same place the `www` record lives):

| Type | Name / Host | Value                    | TTL   |
|------|-------------|--------------------------|-------|
| A    | `mc`        | `YOUR_SERVER_IP`         | 3600  |

Find `YOUR_SERVER_IP` with `curl -4 ifconfig.me` on the server. DNS can take a
few minutes to an hour to propagate. Check it with:

```bash
dig +short mc.theflyingcocker.co.uk    # should print the server's IP
```

> Note: this is a plain DNS record, **not** a website — don't add it in Nginx or
> Certbot. Minecraft connects straight to the IP on UDP 19132.

---

## 2. Firewall — open the game port

Bedrock uses **UDP 19132** (and 19133 for IPv6). Open it. If `ufw` isn't set up
yet, make sure SSH and the web ports stay open too, or you'll lock yourself out:

```bash
ufw allow OpenSSH          # or: ufw allow 22/tcp   -- keep SSH open!
ufw allow 80,443/tcp       # keep the website reachable
ufw allow 19132/udp        # Bedrock (IPv4)
ufw allow 19133/udp        # Bedrock (IPv6) -- harmless if unused
ufw enable                 # says yes; safe as long as SSH is allowed above
ufw status verbose         # confirm the rules
```

---

## 3. Create a dedicated user + folder

Run the game server as its own locked-down user (not `root`, not the web
`deployuser`):

```bash
adduser --system --group --home /opt/minecraft-bedrock minecraft
mkdir -p /opt/minecraft-bedrock
cd /opt/minecraft-bedrock
apt-get update && apt-get install -y unzip curl
```

---

## 4. Download the official Bedrock server

Mojang's download page requires accepting terms, so you copy the current link
from your own browser (the version number changes over time):

1. On any computer, open **https://www.minecraft.net/en-us/download/server/bedrock**
2. Tick the “I agree” checkbox.
3. Right-click the **Download** button → **Copy link address**. It looks like:
   `https://www.minecraft.net/bedrockdedicatedserver/bin-linux/bedrock-server-1.21.XX.XX.zip`

Then, on the server, paste that URL in place of `PASTE_URL_HERE`:

```bash
cd /opt/minecraft-bedrock
curl -A "Mozilla/5.0" -fL "PASTE_URL_HERE" -o bedrock-server.zip
unzip -o bedrock-server.zip
rm bedrock-server.zip
chmod +x bedrock_server
```

> The `-A "Mozilla/5.0"` matters — Mojang's CDN rejects the default download
> agent. If you get a tiny/HTML file instead of a real zip, that's why.

---

## 5. Configure the server

Edit `server.properties`:

```bash
nano /opt/minecraft-bedrock/server.properties
```

Set at least these (leave the rest at their defaults):

```properties
server-name=The Flying Cocker
gamemode=survival
difficulty=easy
allow-cheats=false
max-players=6
online-mode=true
allow-list=true
server-port=19132
server-portv6=19133
view-distance=10
player-idle-timeout=30
default-player-permission-level=member
```

- `online-mode=true` — verifies each player against Xbox Live, so only the real
  owner of a gamertag can use it.
- `allow-list=true` — **only** gamertags on the allow-list can join (next step).
  This is what keeps strangers out.

Save and exit (`Ctrl+O`, `Enter`, `Ctrl+X`).

---

## 6. Allow-list the kids (who can join)

Create the allow-list with each child's **exact in-game gamertag**:

```bash
nano /opt/minecraft-bedrock/allowlist.json
```

```json
[
  { "name": "Kid1Gamertag" },
  { "name": "Kid2Gamertag" },
  { "name": "GrownUpGamertag" }
]
```

Get each gamertag right (it's case-sensitive). Save and exit.

> **To add someone later:** edit `allowlist.json`, add another `{ "name": "..." }`
> line, then restart the server (`systemctl restart minecraft-bedrock`). Or, if
> you run it interactively (see the tip in step 8), type `allowlist add THEIRNAME`
> then `allowlist reload` in the console — no restart needed.

Fix ownership so the `minecraft` user owns everything:

```bash
chown -R minecraft:minecraft /opt/minecraft-bedrock
```

---

## 7. Run it 24/7 with systemd

Create the service:

```bash
cat > /etc/systemd/system/minecraft-bedrock.service <<'EOF'
[Unit]
Description=Minecraft Bedrock Server (The Flying Cocker)
After=network.target

[Service]
User=minecraft
Group=minecraft
WorkingDirectory=/opt/minecraft-bedrock
Environment=LD_LIBRARY_PATH=.
ExecStart=/opt/minecraft-bedrock/bedrock_server
Restart=on-failure
RestartSec=5
KillSignal=SIGINT
# Basic hardening
NoNewPrivileges=true
PrivateTmp=true
ProtectSystem=full

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable --now minecraft-bedrock
```

Check it's up:

```bash
systemctl status minecraft-bedrock --no-pager
journalctl -u minecraft-bedrock -n 30 --no-pager   # recent server log
```

You should see lines ending with `Server started.` and it listening on 19132.

---

## 8. Everyday management

```bash
systemctl start   minecraft-bedrock     # start
systemctl stop    minecraft-bedrock     # stop
systemctl restart minecraft-bedrock     # restart (after editing config/allowlist)
systemctl status  minecraft-bedrock     # is it running?
journalctl -u minecraft-bedrock -f      # watch the live log (Ctrl+C to exit)
```

> **Tip — a live console:** systemd runs the server without an interactive
> console, so you can't type commands like `allowlist add` into it. If you want
> that, run it inside `screen` instead: `apt-get install -y screen`, then as the
> minecraft user `cd /opt/minecraft-bedrock && LD_LIBRARY_PATH=. screen -S mc
> ./bedrock_server`. Detach with `Ctrl+A` then `D`; reattach with
> `screen -r mc`. (You then wouldn't use the systemd service — pick one.)

---

## 9. Back up the worlds

The worlds live in `/opt/minecraft-bedrock/worlds`. A simple nightly backup:

```bash
mkdir -p /opt/minecraft-backups
cat > /etc/cron.d/minecraft-backup <<'EOF'
# Nightly Bedrock world backup at 04:30, keep the last 7 days
30 4 * * * root tar -czf /opt/minecraft-backups/worlds-$(date +\%F).tar.gz -C /opt/minecraft-bedrock worlds && find /opt/minecraft-backups -name 'worlds-*.tar.gz' -mtime +7 -delete
EOF
```

To restore: stop the server, extract a chosen `worlds-YYYY-MM-DD.tar.gz` back
into `/opt/minecraft-bedrock`, `chown -R minecraft:minecraft`, then start again.

---

## 10. Test the connection

- On the members site, open **Minecraps** — the status badge should show
  **Online** within a minute of the server starting.
- In Minecraft (Bedrock) on a device: **Play → Servers → Add Server** →
  address `mc.theflyingcocker.co.uk`, port `19132` → **Save** → **Join**.
- A quick check from another machine (optional): the port shows as open at
  tools like `https://mcsrvstat.us/bedrock/mc.theflyingcocker.co.uk`.

---

## Troubleshooting

| Symptom | Likely cause / fix |
|---------|--------------------|
| Can't connect at all | Port not open → re-check `ufw status` for `19132/udp`. DNS not ready → `dig +short mc.theflyingcocker.co.uk`. |
| “You are not allowed…” | Gamertag not on the allow-list, or spelled differently → fix `allowlist.json`, restart. |
| Service won't start | `journalctl -u minecraft-bedrock -n 50` — usually a missing `LD_LIBRARY_PATH=.` or wrong ownership. Re-run the `chown` in step 6. |
| Downloaded file won't unzip | You saved the HTML page, not the zip → redownload with the `-A "Mozilla/5.0"` flag and a fresh copied link. |
| Status badge stuck “Offline” on the page | Server not running, port closed, or the status service is briefly down — the badge is informational only; try connecting in-game to confirm. |

---

## Upgrading later

When Mojang releases a new version:

```bash
systemctl stop minecraft-bedrock
cd /opt/minecraft-bedrock
cp server.properties permissions.json allowlist.json /opt/minecraft-backups/  # keep your settings
# download the new zip as in step 4, then:
unzip -o bedrock-server.zip     # keeps your worlds/ and configs; overwrites the program
chown -R minecraft:minecraft /opt/minecraft-bedrock
systemctl start minecraft-bedrock
```

Your `worlds/`, `server.properties` and `allowlist.json` are preserved by the
unzip (it only overwrites the program files), but the backup copies above are
there just in case.
