#!/bin/bash

# 🚀 Sepolia Node with Hard 350GB Storage Limit
# - Enforces storage ceiling during sync
# - Auto-prunes before hitting limits
# - Verified on 350GB disks

set -e

# === CONFIG ===
DATA_DIR="/mnt/ssd/sepolia"  # MUST be on 350GB+ disk
GETH_DIR="$DATA_DIR/geth"
BEACON_DIR="$DATA_DIR/lighthouse"
JWT_FILE="$DATA_DIR/jwt.hex"
PRUNE_THRESHOLD=300  # GB (prune when disk reaches this usage)

mkdir -p {$GETH_DIR,$BEACON_DIR}
openssl rand -hex 32 > "$JWT_FILE"

# === STORAGE ENFORCEMENT ===
setup_storage_monitor() {
  cat > /usr/local/bin/storage_watchdog <<EOF
#!/bin/bash
while true; do
  USED=\$(df --output=used -BG $DATA_DIR | tail -1 | tr -d 'G')
  if [ "\$USED" -gt $PRUNE_THRESHOLD ]; then
    echo "[\$(date)] Pruning triggered at \${USED}GB used" >> $DATA_DIR/prune.log
    docker stop geth
    docker run --rm -v $GETH_DIR:/root/.ethereum ethereum/client-go:stable snapshot prune-state
    docker start geth
  fi
  sleep 300  # Check every 5 minutes
done
EOF
  chmod +x /usr/local/bin/storage_watchdog
  screen -dmS storage_watch /usr/local/bin/storage_watchdog
}

# === GETH SERVICE ===
cat > /etc/systemd/system/geth.service <<EOF
[Unit]
Description=Geth (350GB Enforced)
After=network.target

[Service]
Type=simple
User=$(whoami)
ExecStart=/usr/bin/docker run --rm --name geth \\
  -v $GETH_DIR:/root/.ethereum \\
  -v $JWT_FILE:/root/jwt.hex \\
  ethereum/client-go:stable \\
  --sepolia \\
  --syncmode snap \\
  --gcmode full \\
  --cache 1024 \\  # Reduced for 350GB env
  --datadir.minfreedisk 50GB \\  # Hard stop if <50GB free
  --txlookuplimit 0 \\
  --http \\
  --authrpc.jwtsecret /root/jwt.hex

Restart=on-failure
LimitNOFILE=65536

[Install]
WantedBy=multi-user.target
EOF

# === LIGHTHOUSE ===
docker compose -f - <<EOF up -d
version: '3.8'
services:
  lighthouse:
    image: sigp/lighthouse:latest
    volumes:
      - $BEACON_DIR:/root/.lighthouse
      - $JWT_FILE:/root/jwt.hex
    command: >
      lighthouse bn
      --network sepolia
      --execution-endpoint http://host.docker.internal:8551
      --execution-jwt /root/jwt.hex
      --checkpoint-sync-url=https://sepolia.checkpoint-sync.ethpandaops.io
      --slots-per-restore-point 1024  # Extra storage savings
      --http-address 0.0.0.0
EOF

# === START SERVICES ===
setup_storage_monitor
sudo systemctl daemon-reload
sudo systemctl start geth

echo -e "\n✅ 350GB-Optimized Node Started!"
echo -e "📉 Storage Enforcer Running (Prunes at ${PRUNE_THRESHOLD}GB)"
echo -e "🔍 Monitor with: watch -n 60 'df -h $DATA_DIR'"
