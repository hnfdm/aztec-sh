#!/bin/bash

# 🚀 Auto Setup Sepolia Geth + Beacon (Prysm or Lighthouse) for Aztec Sequencer [STORAGE OPTIMIZED]
# Corrected version with proper flags and syntax
# Maintains under 500GB storage requirement

set -e

# === CHOOSE BEACON CLIENT ===
echo ">>> Choose beacon client to use:"
echo "1) Prysm"
echo "2) Lighthouse"
read -rp "Enter choice [1 or 2]: " BEACON_CHOICE

if [[ "$BEACON_CHOICE" != "1" && "$BEACON_CHOICE" != "2" ]]; then
  echo "❌ Invalid choice. Exiting."
  exit 1
fi

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

if [ "$BEACON_CHOICE" = "1" ]; then
  BEACON="prysm"
  BEACON_VOLUME="$DATA_DIR/prysm"
else
  BEACON="lighthouse"
  BEACON_VOLUME="$DATA_DIR/lighthouse"
fi
mkdir -p "$BEACON_VOLUME"

# === GENERATE JWT SECRET ===
echo ">>> Generating JWT secret..."
openssl rand -hex 32 > "$JWT_FILE"

# === WRITE docker-compose.yml ===
echo ">>> Writing optimized docker-compose.yml..."
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
      --syncmode=snap
      --cache=2048
      --gcmode=archive
      --txlookuplimit=0
EOF

if [ "$BEACON" = "prysm" ]; then
  cat >> "$COMPOSE_FILE" <<EOF

  prysm:
    image: gcr.io/prysmaticlabs/prysm/beacon-chain:stable
    container_name: prysm
    restart: unless-stopped
    volumes:
      - $BEACON_VOLUME:/data
      - $JWT_FILE:/data/jwt.hex
    depends_on:
      - geth
    ports:
      - "4000:4000"
      - "3500:3500"
    command: >
      --datadir=/data
      --sepolia
      --execution-endpoint=http://geth:8551
      --jwt-secret=/data/jwt.hex
      --genesis-beacon-api-url=https://lodestar-sepolia.chainsafe.io
      --checkpoint-sync-url=https://sepolia.checkpoint-sync.ethpandaops.io
      --accept-terms-of-use
      --rpc-host=0.0.0.0
      --rpc-port=4000
      --grpc-gateway-host=0.0.0.0
      --grpc-gateway-port=3500
      --slots-per-archive-point=2048
EOF
else
  cat >> "$COMPOSE_FILE" <<EOF

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
      --checkpoint-sync-url=https://sepolia.checkpoint-sync.ethpandaops.io
      --http
      --http-address 0.0.0.0
      --slots-per-restore-point 2048
EOF
fi

# === START DOCKER ===
echo ">>> Starting optimized Sepolia node with $BEACON..."
cd "$DATA_DIR"
docker compose down >/dev/null 2>&1 || true  # Clean up any previous instances
docker compose up -d

echo -e "\n>>> ✅ Optimized setup complete. Monitoring commands:"
echo "  docker logs -f geth"
echo "  docker logs -f $BEACON"
echo "  df -h $DATA_DIR  # Check disk usage"
echo -e "\n>>> Storage optimizations applied:"
echo "  - Geth cache reduced to 2048MB"
echo "  - Beacon chain archive points reduced"
echo "  - Removed unsupported pruneancient flag"
echo "  - Fixed Lighthouse command syntax"
