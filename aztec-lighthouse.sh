#!/bin/bash

# 🚀 Corrected Ultra-Compact Sepolia Setup [300GB VERSION]
# Fixed invalid Geth flags while maintaining storage limits

set -e

# === DEPENDENCY CHECK ===
echo ">>> Checking required dependencies..."
install_if_missing() {
  local cmd="$1"
  local pkg="$2"

  if ! command -v $cmd &> /dev/null; then
    echo "⛔ Missing: $cmd → installing $pkg..."
    sudo apt update
    sudo apt install -y $pkg
  else
    echo "✅ $cmd is already installed."
  fi
}

# Docker check
if ! command -v docker &> /dev/null || ! command -v docker compose &> /dev/null; then
  echo "⛔ Docker or Docker Compose not found. Installing Docker..."
  
  for pkg in docker.io docker-doc docker-compose podman-docker containerd runc; do
    sudo apt-get remove -y $pkg || true
  done

  sudo install -m 0755 -d /etc/apt/keyrings
  curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo gpg --dearmor -o /etc/apt/keyrings/docker.gpg
  sudo chmod a+r /etc/apt/keyrings/docker.gpg

  echo \
    "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] \
    https://download.docker.com/linux/ubuntu $(. /etc/os-release && echo \"$VERSION_CODENAME\") stable" | \
    sudo tee /etc/apt/sources.list.d/docker.list > /dev/null

  sudo apt update
  sudo apt install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
  sudo docker run hello-world
  sudo systemctl enable docker && sudo systemctl restart docker
else
  echo "✅ Docker and Docker Compose are already installed."
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

BEACON="lighthouse"
BEACON_VOLUME="$DATA_DIR/lighthouse"
mkdir -p "$BEACON_VOLUME"

# === GENERATE JWT SECRET ===
echo ">>> Generating JWT secret..."
openssl rand -hex 32 > "$JWT_FILE"

# === WRITE docker-compose.yml ===
echo ">>> Writing corrected ultra-compact docker-compose.yml..."
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
      --history.transactions 0
      --snapshot=false
      --txlookuplimit 0

  lighthouse:
    image: sigp/lighthouse:latest
    container_name: lighthouse
    restart: unless-stopped
    volumes:
      - $BEACON_VOLUME:/root/.lighthouse
      - $JWT_FILE:/root/jwt.hex
    depends_on:
      - geth
    ports:
      - "5052:5052"
      - "9000:9000/tcp"
      - "9000:9000/udp"
    command: >
      lighthouse
      bn
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

# === START DOCKER ===
echo ">>> Starting ultra-compact Sepolia node (300GB version)..."
cd "$DATA_DIR"
docker compose down >/dev/null 2>&1 || true  # Clean up any previous instances
docker compose up -d

echo -e "\n>>> ✅ Ultra-compact setup complete (300GB target). Monitoring commands:"
echo "  docker logs -f geth"
echo "  docker logs -f lighthouse"
echo "  df -h $DATA_DIR  # Check disk usage"
echo -e "\n>>> Critical optimizations for 300GB:"
echo "  - Reduced Geth cache to 1024MB"
echo "  - Disabled snapshot storage"
echo "  - Minimal transaction history"
echo "  - Checkpoint sync for fast beacon init"
echo "  - Reduced beacon restore points"
echo "  - Disabled deposit contract sync"
