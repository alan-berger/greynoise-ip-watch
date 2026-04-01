!/usr/bin/env bash
# greynoise-ip-watch.sh
# Resolves TARGET_HOST, checks GreyNoise Community API,
# notifies via ntfy.sh if IP or reputation status changes.
# Dependencies: curl, jq, dig (dnsutils)

set -uo pipefail

# --- Config ---
TARGET_HOST="your_dyndns_hostname"
GN_API_KEY="your_greynoise_api_key"
NTFY_TOPIC="you_ntfy_topic"
NTFY_SERVER="https://ntfy.sh"
CACHE_FILE="${XDG_CACHE_HOME:-$HOME/.cache}/greynoise-check.cache"
GN_TMP="/tmp/gn_response.json"

# --- Setup ---
mkdir -p "$(dirname "$CACHE_FILE")"

# --- Resolve IP ---
CURRENT_IP=$(dig +short "$TARGET_HOST" A \
    | grep -E '^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$' \
    | head -1)

if [[ -z "$CURRENT_IP" ]]; then
    echo "ERROR: Could not resolve $TARGET_HOST" >&2
    exit 1
fi

# --- Query GreyNoise Community API ---
HTTP_STATUS=$(curl -s --max-time 15 \
    -o "$GN_TMP" \
    -w "%{http_code}" \
    -H "key: $GN_API_KEY" \
    "https://api.greynoise.io/v3/community/${CURRENT_IP}")

if [[ "$HTTP_STATUS" != "200" && "$HTTP_STATUS" != "404" ]]; then
    echo "ERROR: GreyNoise API returned unexpected status $HTTP_STATUS for $CURRENT_IP" >&2
    cat "$GN_TMP" >&2
    exit 1
fi

RESPONSE=$(cat "$GN_TMP")

NOISE=$(echo "$RESPONSE" | jq -r '.noise')
RIOT=$(echo  "$RESPONSE" | jq -r '.riot')
CLASS=$(echo "$RESPONSE" | jq -r '.classification // "unknown"')

CURRENT_STATE="${CURRENT_IP}|${NOISE}|${RIOT}|${CLASS}"

# --- Load cache ---
PREV_STATE=""
[[ -f "$CACHE_FILE" ]] && PREV_STATE=$(cat "$CACHE_FILE")

if [[ "$CURRENT_STATE" == "$PREV_STATE" ]]; then
    echo "$(date -Iseconds) No change: $CURRENT_STATE"
    exit 0
fi

# --- Parse previous state ---
PREV_IP=$(    echo "$PREV_STATE" | cut -d'|' -f1)
PREV_NOISE=$( echo "$PREV_STATE" | cut -d'|' -f2)
PREV_RIOT=$(  echo "$PREV_STATE" | cut -d'|' -f3)

# --- Build notification ---
TITLE="GLaDOS IP reputation change"
PRIORITY="default"
TAGS="mag"
LINES=()

if [[ "$CURRENT_IP" != "$PREV_IP" && -n "$PREV_IP" ]]; then
    LINES+=("IP rotated: ${PREV_IP} → ${CURRENT_IP}")
fi

if [[ "$NOISE" == "true" && "$PREV_NOISE" != "true" ]]; then
    LINES+=("NOISE: IP is now flagged as scanning the internet")
    PRIORITY="high"
    TAGS="rotating_light"
elif [[ "$NOISE" == "false" && "$PREV_NOISE" == "true" ]]; then
    LINES+=("NOISE: IP is no longer flagged as scanning")
fi

if [[ "$RIOT" == "true" && "$PREV_RIOT" != "true" ]]; then
    LINES+=("RIOT: IP entered Common Business Services dataset")
elif [[ "$RIOT" == "false" && "$PREV_RIOT" == "true" ]]; then
    LINES+=("RIOT: IP left Common Business Services dataset")
fi

LINES+=("Classification: ${CLASS}")
LINES+=("Current state: noise=${NOISE} riot=${RIOT} classification=${CLASS}")
LINES+=("https://viz.greynoise.io/ip/${CURRENT_IP}")

MSG=$(printf '%s\n' "${LINES[@]}")

# --- Notify ---
curl -sf --max-time 15 \
    -H "Title: $TITLE" \
    -H "Priority: $PRIORITY" \
    -H "Tags: $TAGS" \
    -d "$MSG" \
    "${NTFY_SERVER}/${NTFY_TOPIC}" > /dev/null || \
    echo "WARNING: ntfy notification failed" >&2

# --- Update cache ---
echo -n "$CURRENT_STATE" > "$CACHE_FILE"
echo "$(date -Iseconds) Change detected and notified: IP=$CURRENT_IP noise=$NOISE riot=$RIOT classification=$CLASS"
