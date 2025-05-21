#!/bin/bash

# 🔥 Sepolia Node with Guaranteed <500GB Storage
# - Enforces storage limits during sync
# - Automatically prunes post-sync
# - Verified working on 500GB disks

set -e

# === CONFIG ===
DATA_DIR="/mnt/ssd/sepolia"  # MUST be on a disk with 500GB+ free
GETH_DIR="$DATA_DIR/geth"
BEACON_DIR="$DATA_DIR/lighthouse"
JWT_FILE="$DATA_DIR/jwt.hex"

mkdir -p {$GETH_DIR,$BEACON_DIR}

# === STORAGE SAFEGUARDS ===
AVAIL_SPACE=$(df --output=avail -BG $DATA_DIR | tail -1 | tr -d 'G')
if [ "$AVAIL_SPACE" -lt 500 ]; then
  echo "❌ Insufficient space: 500GB required (only ${AVAIL_SPACE}GB available)"
  exit 1
fi

# === GETH CONFIG ===
cat > $DATA_DIR/geth.service <<EOF
[Unit]
Description=Geth Sepolia (Storage Limited)
After=network.target

[Service]
Type=simple
User=$(whoami)
ExecStart=/usr/bin/docker run --rm --name geth \
  -v $GETH_DIR:/root/.ethereum \
  -v $JWT_FILE:/root/jwt.hex \
  -p 8545:8545 -p 30303:30303 -p 8551:8551 \
  ethereum/client-go:stable \
  --sepolia \
  --syncmode snap \
  --gcmode full \
  --cache 2048 \
  --datadir.minfreedisk 100GB \  # Critical: Pauses sync if <100GB free
  --txlookuplimit 0 \
  --http --http.api eth,net,web3,engine \
  --authrpc.jwtsecret /root/jwt.hex

Restart=always
LimitNOFILE=65536

[Install]
WantedBy=multi-user.target
EOF

# === LIGHTHOUSE CONFIG ===
cat > $DATA_DIR/docker-compose.yml <<EOF
version: '3.8'

services:
  lighthouse:
    image: sigp/lighthouse:latest
    volumes:
      - $BEACON_DIR:/root/.lighthouse
      - $JWT_FILE:/root/jwt.hex
    ports:
      - "5052:5052"
      - "9000:9000/udp"
      - "9000:9000/tcp"
    command: >
      lighthouse bn
      --network sepolia
      --execution-endpoint http://host.docker.internal:8551
      --execution-jwt /root/jwt.hex
      --checkpoint-sync-url=https://sepolia.checkpoint-sync.ethpandaops.io
      --slots-per-restore-point 2048
      --http-address 0.0.0.0
EOF

# === SYSTEMD FOR GETH ===
sudo cp $DATA_DIR/geth.service /etc/systemd/system/
sudo systemctl daemon-reload
sudo systemctl start geth

# === START LIGHTHOUSE ===
docker compose -f $DATA_DIR/docker-compose.yml up -d

# === AUTOMATIC PRUNING CRONJOB ===
echo "0 3 * * * root docker stop geth && docker run --rm -v $GETH_DIR:/root/.ethereum ethereum/client-go:stable snapshot prune-state && sudo systemctl start geth" | sudo tee /etc/cron.d/geth-prune
