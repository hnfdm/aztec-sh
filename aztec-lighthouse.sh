#!/bin/bash

# 🛠️ Sepolia Beacon-Only Setup (Lighthouse + Remote RPC)
# ✅ No Geth required | Low storage (~50GB)
# 🔧 For non-Aztec use (Aztec requires local Geth)

set -e

# === DEPENDENCY CHECK === (Same as before)
echo ">>> Checking dependencies..."
install_if_missing() {
  local cmd="$1"; local pkg="$2"
  command -v $cmd &>/dev/null || { echo "⛔ Installing $pkg..."; sudo apt update && sudo apt install -y $pkg; }
}

# Docker, curl, openssl, jq checks here...
# (Keep the same dependency checks from your original script)

# === CONFIG ===
DATA_DIR="$HOME/sepolia-beacon"
BEACON_VOLUME="$DATA_DIR/lighthouse"
JWT_FILE="$DATA_DIR/jwt.hex"
COMPOSE_FILE="$DATA_DIR/docker-compose.yml"
mkdir -p "$BEACON_VOLUME"

# === REMOTE RPC SETUP ===
echo -e "\n>>> Enter your Sepolia RPC endpoint (e.g., Infura/Alchemy):"
echo -e "    Format: https://<YOUR_API_KEY>"
read -rp "    RPC URL: " RPC_ENDPOINT

# === GENERATE JWT SECRET ===
openssl rand -hex 32 > "$JWT_FILE"

# === DOCKER COMPOSE ===
cat > "$COMPOSE_FILE" <<EOF
version: '3.8'

services:
  lighthouse:
    image: sigp/lighthouse:latest
    container_name: lighthouse
    restart: unless-stopped
    volumes:
      - $BEACON_VOLUME:/root/.lighthouse
      - $JWT_FILE:/root/jwt.hex
    ports:
      - "5052:5052"   # REST API
      - "9000:9000/tcp" # P2P
      - "9000:9000/udp" # P2P
    command: >
      lighthouse bn
      --network sepolia
      --execution-endpoint $RPC_ENDPOINT
      --execution-jwt /root/jwt.hex
      --checkpoint-sync-url=https://sepolia.checkpoint-sync.ethpandaops.io
      --http
      --http-address 0.0.0.0
      --slots-per-restore-point 2048
EOF

# === START ===
echo ">>> Starting Lighthouse beacon node..."
cd "$DATA_DIR"
docker compose up -d

echo -e "\n✅ Done! Lighthouse running with remote RPC."
echo -e "📡 Sync progress: docker logs -f lighthouse"
echo -e "🌐 API: http://localhost:5052/eth/v1/node/syncing"
