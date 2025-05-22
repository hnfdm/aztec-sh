#!/bin/bash
# aztec-lighthouse.sh - Final Working Version
# Copyright (c) 2024 Your Name

set -e

# === CONFIGURATION ===
DATA_DIR="$HOME/sepolia-node"
GETH_DIR="$DATA_DIR/geth"
JWT_FILE="$DATA_DIR/jwt.hex"
COMPOSE_FILE="$DATA_DIR/docker-compose.yml"
PRUNE_LOG="$DATA_DIR/prune.log"

# === CLEANUP ===
[ -d "$JWT_FILE" ] && { rm -rf "$JWT_FILE"; echo "Removed directory $JWT_FILE"; }

# === DEPENDENCY CHECK ===
echo ">>> Checking requirements..."
command -v docker >/dev/null 2>&1 || { 
  curl -fsSL https://get.docker.com | sudo sh
  sudo usermod -aG docker $USER
}
command -v jq >/dev/null 2>&1 || sudo apt-get install -y jq
command -v openssl >/dev/null 2>&1 || sudo apt-get install -y openssl

# === INITIAL SETUP ===
mkdir -p "$GETH_DIR"
[ ! -f "$JWT_FILE" ] && openssl rand -hex 32 > "$JWT_FILE"

# === DOCKER COMPOSE ===
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
      "--history.state=0",
      "--history.transactions=0"
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
      "--checkpoint-sync-url", "https://sepolia.checkpoint-sync.ethpandaops.io",
      "--http",
      "--http-address", "0.0.0.0",
      "--slots-per-restore-point", "1024"
    ]

  pruner:
    image: ethereum/client-go:stable
    container_name: pruner
    restart: unless-stopped
    volumes:
      - $GETH_DIR:/root/.ethereum
    entrypoint: ["/bin/sh", "-c"]
    command: >
      "while true; do
        echo \"\$(date): Starting prune...\" >> /root/.ethereum/prune.log;
        geth snapshot prune-state \\
          --datadir /root/.ethereum \\
          --max-account-range 4 \\
          --max-storage-range 4 >> /root/.ethereum/prune.log 2>&1;
        echo \"\$(date): Prune completed\" >> /root/.ethereum/prune.log;
        sleep 3600;
      done"
EOF

# === DEPLOYMENT ===
echo ">>> Starting node with working pruner..."
docker compose -f "$COMPOSE_FILE" down >/dev/null 2>&1 || true
docker compose -f "$COMPOSE_FILE" up -d

echo -e "\n✅ Deployment Successful!"
echo "📊 Monitor pruning: docker exec geth tail -f /root/.ethereum/prune.log"
echo "⏰ Hourly pruning active (first run in 1 hour)"
echo "💻 Geth logs: docker logs -f geth"
