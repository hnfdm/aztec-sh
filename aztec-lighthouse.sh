#!/bin/bash

# 🚀 Auto-Pruning Sepolia Geth + Lighthouse [300GB VERSION]
# Features automatic storage pruning while maintaining archive mode

set -e

# === DEPENDENCY CHECK ===
echo ">>> Checking required dependencies..."
install_if_missing() {
  local cmd="$1"
  local pkg="$2"
  command -v $cmd >/dev/null 2>&1 || {
    echo "⛔ Missing: $cmd → installing $pkg..."
    sudo apt update && sudo apt install -y $pkg
  }
}

# Docker setup
if ! command -v docker &>/dev/null; then
  echo "⛔ Docker not found. Installing..."
  curl -fsSL https://get.docker.com | sudo sh
  sudo usermod -aG docker $USER
  newgrp docker
fi

install_if_missing curl curl
install_if_missing openssl openssl
install_if_missing jq jq

# === CONFIG ===
DATA_DIR="$HOME/sepolia-node"
GETH_DIR="$DATA_DIR/geth"
JWT_FILE="$DATA_DIR/jwt.hex"
COMPOSE_FILE="$DATA_DIR/docker-compose.yml"
mkdir -p "$GETH_DIR"

# === GENERATE JWT SECRET ===
echo ">>> Generating JWT secret..."
openssl rand -hex 32 > "$JWT_FILE"

# === WRITE docker-compose.yml ===
cat > "$COMPOSE_FILE" <<EOF
version: '3.8'

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
    command: >
      --sepolia
      --http
      --http.addr 0.0.0.0
      --http.api eth,web3,net,engine
      --authrpc.addr 0.0.0.0
      --authrpc.port 8551
      --authrpc.jwtsecret /root/jwt.hex
      --authrpc.vhosts=*
      --http.corsdomain="*"
      --syncmode snap
      --cache 1024
      --gcmode archive
      --txlookuplimit 0
      --pruneancient
      --datadir.ancient=/root/.ethereum/sepolia/geth/chaindata/ancient
      --snapshot=false

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
    command: >
      lighthouse bn
      --network sepolia
      --execution-endpoint http://geth:8551
      --execution-jwt /root/jwt.hex
      --checkpoint-sync-url https://sepolia.checkpoint-sync.ethpandaops.io
      --http
      --http-address 0.0.0.0
      --slots-per-restore-point 1024
      --reconstruct-historic-states
      --disable-deposit-contract-sync
EOF

# === START SERVICES ===
echo ">>> Starting auto-pruning node (300GB target)..."
docker compose -f "$COMPOSE_FILE" down >/dev/null 2>&1 || true
docker compose -f "$COMPOSE_FILE" up -d

echo -e "\n✅ Deployment Complete! Auto-pruning is enabled."
echo "📊 Monitor storage usage with: df -h $DATA_DIR"
echo "🔍 Check pruning status: docker exec geth geth db stats | grep Ancient"
echo "📜 View Geth logs: docker logs -f geth"
echo "💡 Note: Initial sync may take 24-48 hours"
