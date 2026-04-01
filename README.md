# greynoise-ip-watch.sh

![Shell](https://img.shields.io/badge/shell-bash-4EAA25?logo=gnubash&logoColor=white)
![Platform](https://img.shields.io/badge/platform-linux-blue?logo=linux&logoColor=white)
![API](https://img.shields.io/badge/API-GreyNoise-FF6B35?logo=greynoise&logoColor=white)
![Notifications](https://img.shields.io/badge/notifications-ntfy.sh-purple)
![License](https://img.shields.io/badge/license-MIT-green)

A Bash script that resolves a dynamic DNS hostname to its current IP address, checks it against the [GreyNoise Community API](https://docs.greynoise.io/reference/get_v3-community-ip), and sends a push notification via [ntfy.sh](https://ntfy.sh) if the IP or its reputation status changes.

## Features

- Resolves a hostname to its current IPv4 address via `dig`
- Queries the GreyNoise Community API for noise, RIOT, and classification status
- Detects and alerts on IP rotation
- Detects and alerts on reputation changes (noise/RIOT flags, classification)
- State caching — only notifies on change, not every run
- Push notifications via ntfy.sh with priority and tag escalation for flagged IPs
- Structured log output suitable for logrotate

## Requirements

| Dependency | Package (Debian/Ubuntu) |
|------------|------------------------|
| `curl`     | `curl`                 |
| `jq`       | `jq`                   |
| `dig`      | `dnsutils`             |

Install all dependencies:

```bash
sudo apt install -y curl jq dnsutils
```

## Configuration

Edit the config block at the top of the script:

```bash
TARGET_HOST="your_dyndns_hostname"   # Hostname to monitor, e.g. glados.example.com
GN_API_KEY="your_greynoise_api_key"  # GreyNoise API key (free tier supported)
NTFY_TOPIC="your_ntfy_topic"         # ntfy.sh topic name
NTFY_SERVER="https://ntfy.sh"        # ntfy server (change if self-hosting)
```

A GreyNoise account is required. The free Community tier supports up to 25 requests/hour, which is sufficient for this script. Sign up at [greynoise.io](https://www.greynoise.io/).

## Usage

Make the script executable and run it:

```bash
chmod +x greynoise-ip-watch.sh
./greynoise-ip-watch.sh
```

### First run

The first run populates the cache. If the IP is clean, it will log a change (from empty state to current state) and send a notification. Subsequent runs will only notify if something changes.

### Example output

No change:
```
2026-04-01T04:41:06+01:00 No change: 86.156.99.24|false|false|unknown
```

Change detected:
```
2026-04-01T04:41:06+01:00 Change detected and notified: IP=86.156.99.24 noise=false riot=false classification=unknown
```

## GreyNoise Fields

| Field            | Description |
|------------------|-------------|
| `noise`          | `true` if the IP has been observed scanning the internet by GreyNoise sensors |
| `riot`           | `true` if the IP is in the Common Business Services dataset (e.g. Google, AWS) |
| `classification` | GreyNoise's verdict: `malicious`, `benign`, or `unknown` |

For a home server IP, `noise=false`, `riot=false`, and `classification=unknown` is the expected and desired state.

The Community API returns HTTP `404` when an IP has never been observed — this is a clean result, not an error, and the script handles it correctly.

## ntfy Notifications

Notifications are sent when any of the following change:

- The resolved IP address (IP rotation)
- `noise` status
- `riot` status
- `classification`

If the IP is flagged as scanning (`noise=true`), the notification priority is escalated to `high` and the tag is set to `rotating_light`. Otherwise priority is `default` with a `mag` tag.

## Cron Setup

Run every 6 hours:

```bash
crontab -e
```

```
0 */6 * * * /path/to/greynoise-ip-watch.sh >> /var/log/greynoise-ip-watch.log 2>&1
```

## Log Rotation

Create `/etc/logrotate.d/greynoise-ip-watch`:

```
/var/log/greynoise-ip-watch.log {
    weekly
    rotate 12
    compress
    missingok
    notifempty
    create 0644 your_username your_username
}
```

Replace `your_username` with the user running the cron job. This retains approximately 3 months of compressed logs.

If logging to `/var/log/`, ensure your user owns the log file:

```bash
sudo touch /var/log/greynoise-ip-watch.log
sudo chown your_username:your_username /var/log/greynoise-ip-watch.log
```

## Cache

State is stored in `~/.cache/greynoise-ip-watch.cache` (or `$XDG_CACHE_HOME/greynoise-ip-watch.cache` if set). Delete it to force a fresh notification on the next run:

```bash
rm ~/.cache/greynoise-ip-watch.cache
```
