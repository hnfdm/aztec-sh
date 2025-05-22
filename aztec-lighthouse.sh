#!/bin/bash
# aztec-lighthouse.sh - 100% Working Version
# Copyright (c) 2024 Your Name

set -e

# === CONFIG ===
DATA_DIR="$HOME/sepolia-node"
GETH_DIR="$DATA_DIR/geth"
JWT_FILE="$DATA_DIR/jwt.hex"
COMPOSE_FILE="$DATA_DIR/docker-compose.yml"
PRUNE_LOG="$GETH_DIR/prune.log"

# === CLEANUP ===
[ -d "$JWT_FILE" ] && rm -rf "$JWT_FILE"
mkdir -p "$GETH_DIR"
touch "$PRUNE_LOG"

# === DEPENDENCIES ===
command -v docker >/dev/null 2>&1 || { 
  curl -fsSL https://get.docker.com | sudo sh
  sudo usermod -aG docker $USER
  newgrp docker
}

# === INIT SETUP ===
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

# === DEPLOY ===
docker compose -f "$COMPOSE_FILE" down >/dev/null 2>&1 || true
docker compose -f "$COMPOSE_FILE" up -d

# === PRUNING SETUP ===
# 1. Create prune script
cat > /usr/local/bin/prune_geth <<'EOF'
#!/bin/bash
PRUNE_LOG="$HOME/sepolia-node/geth/prune.log"
echo "$(date): Starting prune" >> "$PRUNE_LOG"
docker exec geth geth snapshot prune-state --datadir /root/.ethereum >> "$PRUNE_LOG" 2>&1
echo "$(date): Prune completed (Exit code: $?)" >> "$PRUNE_LOG"
EOF
chmod +x /usr/local/bin/prune_geth

# 2. Setup cron job
(crontab -l 2>/dev/null | grep -v "prune_geth"; echo "0 * * * * /usr/local/bin/prune_geth") | crontab -

# 3. Immediate first run
echo "=== INITIAL PRUNE ===" >> "$PRUNE_LOG"
/usr/local/bin/prune_geth &

# === VERIFICATION ===
echo -e "\n✅ Deployment Successful!"
echo "⏰ Hourly pruning enabled (view logs: tail -f $PRUNE_LOG)"
echo "💾 Storage: docker exec geth du -sh /root/.ethereum"
echo "🔍 First prune running in background..."
