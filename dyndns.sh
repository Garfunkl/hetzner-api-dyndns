#!/usr/bin/env bash
# Hetzner Cloud DNS A‑Record Updater 
# ---------------------------------- 
# This script updates a single A record inside a Hetzner Cloud DNS zone 
# based on the machine's current public IPv4 address. 
# 
# It uses the new Hetzner Cloud DNS API (RRsets) and replaces the
# entire A‑record RRset with the current IP if it has changed. 
#
#Requirements: 
# - bash 
# - curl # - jq
# 
# Environment variables: 
# HETZNER_API_TOKEN - Hetzner Cloud API token 
# HETZNER_ZONE_NAME - DNS zone name (e.g. example.com) 
# HETZNER_RECORD_NAME - Record name (e.g. dyn)
# HETZNER_TTL - TTL value (default: 60) 
# 
# Created by Garfunkl, with help from Microsoft Copilot. #
set -euo pipefail

API_TOKEN="${HETZNER_API_TOKEN:-}"
ZONE_NAME="${HETZNER_ZONE_NAME:-}"
RECORD_NAME="${HETZNER_RECORD_NAME:-}"
TTL="${HETZNER_TTL:-60}"

log() {
    printf "%s [%s] %s\n" "$(date '+%Y-%m-%d %H:%M:%S')" "$1" "$2"
}

# --- Validate environment variables ---
if [[ -z "$API_TOKEN" || -z "$ZONE_NAME" || -z "$RECORD_NAME" ]]; then
    log "ERROR" "Missing required environment variables."
    exit 1
fi

# --- Get current public IPv4 ---
CURRENT_IP="$(curl -s4 https://ip.hetzner.com || true)"

if ! [[ "$CURRENT_IP" =~ ^([0-9]+\.){3}[0-9]+$ ]]; then
    log "ERROR" "Could not determine public IPv4 address."
    exit 1
fi

log "INFO" "Current public IP: $CURRENT_IP"

# --- Fetch zone ID ---
ZONE_JSON="$(curl -s \
    -H "Authorization: Bearer $API_TOKEN" \
    "https://api.hetzner.cloud/v1/zones?name=${ZONE_NAME}"
)"

ZONE_ID="$(jq -r '.zones[0].id' <<< "$ZONE_JSON")"

if [[ -z "$ZONE_ID" || "$ZONE_ID" == "null" ]]; then
    log "ERROR" "Zone '$ZONE_NAME' not found."
    exit 1
fi

log "INFO" "Zone ID: $ZONE_ID"

# --- Fetch RRset for the A record ---
RRSETS_JSON="$(curl -s \
    -H "Authorization: Bearer $API_TOKEN" \
    "https://api.hetzner.cloud/v1/zones/${ZONE_ID}/rrsets?name=${RECORD_NAME}&type=A"
)"

RRSET_COUNT="$(jq '.rrsets | length' <<< "$RRSETS_JSON")"

# --- Create record if missing ---
if (( RRSET_COUNT == 0 )); then
    log "INFO" "Record does not exist — creating new A RRset."

    curl -s -X POST \
        -H "Authorization: Bearer $API_TOKEN" \
        -H "Content-Type: application/json" \
        -d "{
            \"name\": \"${RECORD_NAME}\",
            \"type\": \"A\",
            \"ttl\": ${TTL},
            \"records\": [{\"value\": \"${CURRENT_IP}\"}]
        }" \
        "https://api.hetzner.cloud/v1/zones/${ZONE_ID}/rrsets" >/dev/null

    log "INFO" "Record created."
    exit 0
fi

# --- Extract current DNS value ---
OLD_IP="$(jq -r '.rrsets[0].records[0].value' <<< "$RRSETS_JSON")"

log "INFO" "Current DNS IP: $OLD_IP"

# --- Compare ---
if [[ "$OLD_IP" == "$CURRENT_IP" ]]; then
    log "INFO" "No update needed."
    exit 0
fi

log "INFO" "Updating A record…"

# --- Update RRset ---
curl -s -X PUT \
    -H "Authorization: Bearer $API_TOKEN" \
    -H "Content-Type: application/json" \
    -d "{
        \"name\": \"${RECORD_NAME}\",
        \"type\": \"A\",
        \"ttl\": ${TTL},
        \"records\": [{\"value\": \"${CURRENT_IP}\"}]
    }" \
    "https://api.hetzner.cloud/v1/zones/${ZONE_ID}/rrsets" >/dev/null

log "INFO" "Record updated successfully."
exit 0
