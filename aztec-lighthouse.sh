#!/bin/bash
# aztec-lighthouse.sh - Complete Auto-Pruning Solution with State Scheme
# Copyright (c) 2024 Your Name

set -e

# === CONFIGURATION ===
DATA_DIR="$HOME/sepolia-node"
GETH_DIR="$DATA_DIR/geth"
JWT_FILE="$DATA_DIR/jwt.hex"
COMPOSE_FILE="$DATA_DIR/docker-compose.yml"
PRUNE_LOG="$GETH_DIR/prune.log"
STATE_SCHEME="path"  # Options: "hash" (default) or "path" (recommended for pruning)

# === CLEANUP ===
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
      "--history.transactions=0",
      "--state.scheme", "$STATE_SCHEME"
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

# Check disk space
DISK_USAGE=$(df -h /root/sepolia-node | awk 'NR==2 {print $5}' | tr -d '%')
if [ "$DISK_USAGE" -gt 95 ]; then
  echo "$(date): ERROR - Disk usage $DISK_USAGE%, skipping prune" >> "$LOG"
  exit 1
fi

# Check sync status
SYNC=$(curl -s -X POST -H "Content-Type: application/json" \
  --data '{"jsonrpc":"2.0","method":"eth_syncing","params":[],"id":1}' \
  http://localhost:8545 | jq -r '.result')

if [ "$SYNC" != "false" ]; then
  echo "$(date): Skipping prune - Geth syncing" >> "$LOG"
  exit 0
fi

# Check beacon sync
BEACON_SYNC=$(curl -s http://localhost:5052/eth/v1/node/syncing | jq -r '.data.is_syncing')
if [ "$BEACON_SYNC" == "true" ]; then
  echo "$(date): Skipping prune - Beacon chain syncing" >> "$LOG"
  exit 0
fi

echo "$(date): Starting safe prune" >> "$LOG"
docker exec geth geth snapshot prune-state --datadir /root/.ethereum --cache 512 2>&1 | tee -a "$LOG"
PRUNE_EXIT=$?
echo "$(date): Prune completed (Exit: $PRUNE_EXIT)" >> "$LOG"
exit $PRUNE_EXIT
EOF

# 2. Make executable
sudo chmod +x /usr/local/bin/prune_geth

# 3. Setup hourly cron job at random minute
CRON_MINUTE=$(( RANDOM % 60 ))
(crontab -l 2>/dev/null | grep -v "prune_geth"; echo "$CRON_MINUTE * * * * /usr/local/bin/prune_geth") | crontab -

# === DEPLOYMENT ===
docker compose -f "$COMPOSE_FILE" down >/dev/null 2>&1 || true
docker compose -f "$COMPOSE_FILE" up -d

# === VERIFICATION ===
echo -e "\n\033[1;32m✅ Deployment Successful!\033[0m"
echo -e "\n\033[1;34m=== Node Configuration ===\033[0m"
echo "State Scheme:    $STATE_SCHEME"
echo "Prune Schedule:  Every hour at :$CRON_MINUTE"
echo "Storage Target:  <300GB (currently: $(docker exec geth du -sh /root/.ethereum | awk '{print $1}'))"

echo -e "\n\033[1;34m=== Monitoring Commands ===\033[0m"
echo "Prune Logs:      tail -f $PRUNE_LOG"
echo "Geth Sync:       curl -s -X POST -H \"Content-Type: application/json\" --data '{\"jsonrpc\":\"2.0\",\"method\":\"eth_syncing\",\"params\":[],\"id\":1}' http://localhost:8545 | jq"
echo "Lighthouse Sync: curl -s http://localhost:5052/eth/v1/node/syncing | jq"
echo "Storage Usage:   docker exec geth du -sh /root/.ethereum"

# Initial test prune
echo -e "\n\033[1;34m=== Initial Prune Test ===\033[0m"
/usr/local/bin/prune_geth &
