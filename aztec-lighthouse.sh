#!/bin/bash
# aztec-lighthouse.sh - Sepolia Node with Hourly Auto-Pruning [300GB]
# Copyright (c) 2024 Your Name

set -e

# === CONFIGURATION ===
DATA_DIR="$HOME/sepolia-node"
GETH_DIR="$DATA_DIR/geth"
JWT_FILE="$DATA_DIR/jwt.hex"
COMPOSE_FILE="$DATA_DIR/docker-compose.yml"
PRUNE_LOG="$DATA_DIR/prune.log"

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
openssl rand -hex 32 > "$JWT_FILE"

# === DOCKER COMPOSE SETUP ===
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
      "--checkpoint-sync-url", "https://sepolia.beaconstate.info",
      "--http",
      "--http-address", "0.0.0.0",
      "--slots-per-restore-point", "1024",
      "--reconstruct-historic-states"
    ]

  pruner:
    image: ethereum/client-go:stable
    container_name: pruner
    restart: on-failure
    volumes:
      - ${GETH_DIR}:/root/.ethereum
      - ${DATA_DIR}:/host
    command: [
      "sh", "-c",
      "while true; do
        geth snapshot prune-state --datadir /root/.ethereum \
          --max-account-range 4 --max-storage-range 4 >> /host/prune.log 2>&1
        sleep 3600
      done"
    ]
EOF

# === DEPLOYMENT ===
echo ">>> Starting Aztec-compatible node with hourly pruning..."
docker compose -f "$COMPOSE_FILE" down >/dev/null 2>&1 || true
GETH_DIR="$GETH_DIR" JWT_FILE="$JWT_FILE" DATA_DIR="$DATA_DIR" \
docker compose -f "$COMPOSE_FILE" up -d

# === MONITORING TOOLS ===
cat > "$DATA_DIR/monitor-pruning.sh" <<'EOF'
#!/bin/bash
echo "=== PRUNING STATUS ==="
echo -n "Last run: "
grep "Pruning successful" "$HOME/sepolia-node/prune.log" | tail -1 | cut -d' ' -f1-3 || echo "Never"
echo -n "Storage:  "
du -sh "$HOME/sepolia-node/geth" | awk '{print $1}'
echo "Live logs: tail -f $HOME/sepolia-node/prune.log"
EOF
chmod +x "$DATA_DIR/monitor-pruning.sh"

# === VERIFICATION ===
echo -e "\n✅ Aztec Sepolia Node with Hourly Pruning Ready!"
echo "📊 Monitor: $DATA_DIR/monitor-pruning.sh"
echo "📝 Logs: tail -f $PRUNE_LOG"
echo "⚡ Pruning runs hourly in background"
echo "💡 First prune will execute automatically within 1 hour"

# Health check running in background
(while true; do
  if ! docker ps | grep -q geth; then
    echo "⚠️  Geth container stopped! Check logs: docker logs geth" >&2
    exit 1
  fi
  sleep 300
done) &
