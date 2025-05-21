#!/bin/bash

# 🚀 Corrected Sepolia Geth + Lighthouse [300GB VERSION]
# Fixed command formatting issues

set -e

# === CONFIG ===
DATA_DIR="$HOME/sepolia-node"
GETH_DIR="$DATA_DIR/geth"
JWT_FILE="$DATA_DIR/jwt.hex"
COMPOSE_FILE="$DATA_DIR/docker-compose.yml"
mkdir -p "$GETH_DIR"

# === WRITE docker-compose.yml ===
cat > "$COMPOSE_FILE" <<'EOF'
services:
  geth:
    image: ethereum/client-go:stable
    container_name: geth
    restart: unless-stopped
    volumes:
      - ${GETH_DIR}:/root/.ethereum
      - ${JWT_FILE}:/root/jwt.hex
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
      "--snapshot=false",
      "--history.state=0",
      "--history.transactions=0"
    ]

  lighthouse:
    image: sigp/lighthouse:latest
    container_name: lighthouse
    restart: unless-stopped
    volumes:
      - ${DATA_DIR}/lighthouse:/root/.lighthouse
      - ${JWT_FILE}:/root/jwt.hex
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
      "--slots-per-restore-point", "1024",
      "--reconstruct-historic-states",
      "--disable-deposit-contract-sync"
    ]
EOF

# === START SERVICES ===
echo ">>> Starting services with proper command formatting..."
GETH_DIR="$GETH_DIR" JWT_FILE="$JWT_FILE" DATA_DIR="$DATA_DIR" \
docker compose -f "$COMPOSE_FILE" down >/dev/null 2>&1 || true
GETH_DIR="$GETH_DIR" JWT_FILE="$JWT_FILE" DATA_DIR="$DATA_DIR" \
docker compose -f "$COMPOSE_FILE" up -d

echo -e "\n✅ Deployment Complete with Proper Command Formatting"
echo "📊 Monitor storage: df -h $DATA_DIR"
echo "🔍 Check Geth logs: docker logs -f geth"
echo "🔍 Check Lighthouse logs: docker logs -f lighthouse"
