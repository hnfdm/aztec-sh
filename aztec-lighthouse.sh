#!/bin/bash
# aztec-lighthouse.sh - Fixed Version with Directory Handling
# Copyright (c) 2024 Your Name

set -e

# === CONFIGURATION ===
DATA_DIR="$HOME/sepolia-node"
GETH_DIR="$DATA_DIR/geth"
JWT_FILE="$DATA_DIR/jwt.hex"
COMPOSE_FILE="$DATA_DIR/docker-compose.yml"
PRUNE_LOG="$DATA_DIR/prune.log"

# === CLEANUP PREVIOUS ERRORS ===
# Remove if jwt.hex is a directory
[ -d "$JWT_FILE" ] && {
  echo "⚠️  Found directory at $JWT_FILE - cleaning up..."
  rm -rf "$JWT_FILE"
}

# === DEPENDENCY CHECK ===
echo ">>> Checking system requirements..."
command -v docker >/dev/null 2>&1 || { 
  echo "⛔ Docker not found. Installing...";
  curl -fsSL https://get.docker.com | sudo sh;
  sudo usermod -aG docker $USER;
}
command -v jq >/dev/null 2>&1 || sudo apt-get install -y jq
command -v openssl >/dev/null 2>&1 || sudo apt-get install -y openssl

# === INITIAL SETUP ===
mkdir -p "$GETH_DIR"
[ ! -f "$JWT_FILE" ] && openssl rand -hex 32 > "$JWT_FILE"

# === DOCKER COMPOSE SETUP ===
cat > "$COMPOSE_FILE" <<EOF
services:
  geth:
    image: ethereum/client-go:stable
    container_name: geth
    restart: unless-stopped
    volumes:
      - $GETH_DIR:/root/.ethereum
      - $JWT_FILE:/root/jwt.hex
    ports:
      - "8545:8545"
      - "30303:30303"
      - "8551:8551"
    command: [
      "--sepolia",
      "--http",
      "--http.addr", "0.0.0.0",
      "--http.api", "eth,web3,net,engine",
      "--authrpc.addr", "0.0.0.0",
      "--authrpc.port", "8551",
      "--authrpc.jwtsecret", "/root/jwt.hex",
      "--authrpc.vhosts=*",
      "--http.corsdomain=*",
      "--syncmode", "snap",
      "--cache", "1024",
      "--gcmode", "archive",
      "--txlookuplimit", "0",
      "--snapshot",
      "--prune",
      "--prune.storage.older", "1h",
      "--prune.history.older", "1h"
    ]

  lighthouse:
    image: sigp/lighthouse:latest
    container_name: lighthouse
    restart: unless-stopped
    volumes:
      - $DATA_DIR/lighthouse:/root/.lighthouse
      - $JWT_FILE:/root/jwt.hex
    depends_on:
      - geth
    ports:
      - "5052:5052"
      - "9000:9000/tcp"
      - "9000:9000/udp"
    command: [
      "lighthouse", "bn",
      "--network", "sepolia",
      "--execution-endpoint", "http://geth:8551",
      "--execution-jwt", "/root/jwt.hex",
      "--checkpoint-sync-url", "https://sepolia.beaconstate.info",
      "--http",
      "--http-address", "0.0.0.0",
      "--slots-per-restore-point", "1024",
      "--reconstruct-historic-states"
    ]
EOF

# === DEPLOYMENT ===
echo ">>> Starting Aztec-compatible node..."
docker compose -f "$COMPOSE_FILE" down >/dev/null 2>&1 || true
docker compose -f "$COMPOSE_FILE" up -d

echo -e "\n✅ Deployment Successful!"
echo "📊 Monitor: docker logs -f geth"
echo "🔧 Auto-pruning runs hourly in background"
