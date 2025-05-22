#!/bin/bash
# aztec-lighthouse.sh - Complete Auto-Pruning Solution
# Copyright (c) 2024 Your Name

set -e

# === CONFIGURATION ===
DATA_DIR="$HOME/sepolia-node"
GETH_DIR="$DATA_DIR/geth"
JWT_FILE="$DATA_DIR/jwt.hex"
COMPOSE_FILE="$DATA_DIR/docker-compose.yml"
PRUNE_LOG="$GETH_DIR/prune.log"

# === CLEANUP PREVIOUS INSTALLS ===
[ -d "$JWT_FILE" ] && rm -rf "$JWT_FILE"
mkdir -p "$GETH_DIR"
touch "$PRUNE_LOG"

# === DEPENDENCIES ===
command -v docker >/dev/null 2>&1 || {
  echo "Installing Docker..."
  curl -fsSL https://get.docker.com | sudo sh
  sudo usermod -aG docker $USER
  newgrp docker
}
command -v jq >/dev/null 2>&1 || sudo apt-get install -y jq
command -v openssl >/dev/null 2>&1 || sudo apt-get install -y openssl

# === INITIAL SETUP ===
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
EOF

# === PRUNING SYSTEM ===
# 1. Create smart prune script
sudo tee /usr/local/bin/prune_geth <<'EOF' >/dev/null
#!/bin/bash
LOG="$HOME/sepolia-node/geth/prune.log"

# Wait for Geth to be responsive
for i in {1..10}; do
  if curl -s -X POST -H "Content-Type: application/json" \
    --data '{"jsonrpc":"2.0","method":"eth_blockNumber","params":[],"id":1}' \
    http://localhost:8545 >/dev/null; then
    break
  fi
  sleep 6
done

# Get sync status
SYNC=$(curl -s -X POST -H "Content-Type: application/json" \
  --data '{"jsonrpc":"2.0","method":"eth_syncing","params":[],"id":1}' \
  http://localhost:8545 | jq -r '.result')

if [ "$SYNC" != "false" ]; then
  echo "$(date): Skipping prune - Geth syncing (Progress: $SYNC)" >> "$LOG"
  exit 0
fi

# Check Lighthouse
LIGHTHOUSE_STATUS=$(curl -s http://localhost:5052/eth/v1/node/syncing | jq -r '.data.is_syncing')
if [ "$LIGHTHOUSE_STATUS" == "true" ]; then
  echo "$(date): Skipping prune - Beacon chain syncing" >> "$LOG"
  exit 0
fi

echo "$(date): Starting safe prune" >> "$LOG"
docker exec geth geth snapshot prune-state --datadir /root/.ethereum 2>&1 | tee -a "$LOG"
PRUNE_EXIT=$?
echo "$(date): Prune completed (Exit: $PRUNE_EXIT)" >> "$LOG"
exit $PRUNE_EXIT
EOF

# 2. Make executable
sudo chmod +x /usr/local/bin/prune_geth

# 3. Setup hourly cron job at a random minute to avoid load spikes
CRON_MINUTE=$(( RANDOM % 60 ))
(crontab -l 2>/dev/null | grep -v "prune_geth"; echo "$CRON_MINUTE * * * * /usr/local/bin/prune_geth") | crontab -

# === DEPLOYMENT ===
docker compose -f "$COMPOSE_FILE" down >/dev/null 2>&1 || true
docker compose -f "$COMPOSE_FILE" up -d

# === VERIFICATION ===
echo -e "\n\033[1;32m✅ Deployment Successful!\033[0m"
echo -e "\n\033[1;34m=== Monitoring Commands ===\033[0m"
echo "Prune Logs:      tail -f $PRUNE_LOG"
echo "Geth Sync:       curl -s -X POST -H \"Content-Type: application/json\" --data '{\"jsonrpc\":\"2.0\",\"method\":\"eth_syncing\",\"params\":[],\"id\":1}' http://localhost:8545 | jq"
echo "Lighthouse Sync: curl -s http://localhost:5052/eth/v1/node/syncing | jq"
echo "Storage Usage:   docker exec geth du -sh /root/.ethereum"
echo -e "\n\033[1;34m=== Automatic Pruning ===\033[0m"
echo "• Runs hourly at :$CRON_MINUTE"
echo "• Will auto-activate when sync completes"
echo "• First test run starting now..."

# Initial test
/usr/local/bin/prune_geth &
