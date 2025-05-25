#!/bin/bash

# Function to validate private key format
validate_private_key() {
    local key=$1
    if [[ ! $key =~ ^0x[0-9a-fA-F]{64}$ ]]; then
        echo -e "\033[31mError: Invalid private key format. Must be 64-character hex string with 0x prefix.\033[0m"
        return 1
    fi
    return 0
}

# Function to validate RPC endpoint
validate_rpc_endpoint() {
    local endpoint=$1
    if [[ ! $endpoint =~ ^https?:// ]]; then
        echo -e "\033[31mError: RPC endpoint must start with http:// or https://\033[0m"
        return 1
    fi
    return 0
}

# Prompt for private key
while true; do
    echo -e "\033[34mEnter your private key (0x-prefixed 64-character hex string): \033[0m"
    read -s PRIVATE_KEY
    if validate_private_key "$PRIVATE_KEY"; then
        break
    fi
done

# Prompt for blockchain RPC endpoint
while true; do
    echo -e "\033[34mEnter your blockchain RPC endpoint (e.g., https://0g-testnet.rpc.0g.ai): \033[0m"
    read -r RPC_ENDPOINT
    if validate_rpc_endpoint "$RPC_ENDPOINT"; then
        break
    fi
done

# Test RPC endpoint connectivity
echo "Testing RPC endpoint connectivity..."
if ! curl -s -X POST -H "Content-Type: application/json" --data '{"jsonrpc":"2.0","method":"eth_blockNumber","params":[],"id":1}' "$RPC_ENDPOINT" >/dev/null; then
    echo -e "\033[33mWarning: Could not connect to RPC endpoint. Proceeding anyway, but verify the endpoint is correct.\033[0m"
else
    echo -e "\033[32mRPC endpoint is reachable.\033[0m"
fi

# Step 1: Install dependencies
echo "Installing dependencies..."
sudo apt-get update
sudo apt-get install -y clang cmake build-essential openssl pkg-config libssl-dev jq

# Step 2: Install Go (skip if already installed)
if ! command -v go &> /dev/null; then
    echo "Installing Go..."
    cd $HOME
    ver="1.22.0"
    wget "https://golang.org/dl/go$ver.linux-amd64.tar.gz"
    sudo rm -rf /usr/local/go
    sudo tar -C /usr/local -xzf "go$ver.linux-amd64.tar.gz"
    rm "go$ver.linux-amd64.tar.gz"
    echo "export PATH=$PATH:/usr/local/go/bin:$HOME/go/bin" >> ~/.bash_profile
    source ~/.bash_profile
    go version
else
    echo "Go is already installed, skipping..."
fi

# Step 3: Install or update rustup
echo "Checking Rust and rustup installation..."
if command -v rustc &> /dev/null && [[ $(rustc --version) == *"nightly"* || $(rustc --version) == *"beta"* ]]; then
    echo -e "\033[33mWarning: Non-stable Rust version detected. The 0g storage node requires a stable Rust version.\033[0m"
fi
if command -v rustup &> /dev/null; then
    echo "rustup is already installed, updating..."
    rustup update stable || { echo -e "\033[31mFailed to update rustup.\033[0m"; exit 1; }
else
    echo "Installing rustup..."
    curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y --default-toolchain stable || { echo -e "\033[31mFailed to install rustup.\033[0m"; exit 1; }
    . "$HOME/.cargo/env"
fi

# Ensure stable toolchain
echo "Setting Rust stable toolchain..."
rustup default stable || { echo -e "\033[31mFailed to set stable toolchain.\033[0m"; exit 1; }
rustc --version

# Step 4: Download and build 0g-storage-node
echo "Downloading and building 0g-storage-node..."
cd $HOME
rm -rf 0g-storage-node
git clone https://github.com/0glabs/0g-storage-node.git
cd 0g-storage-node
git checkout v0.8.7
git submodule update --init --recursive
cargo build --release || { echo -e "\033[31mBuild failed.\033[0m"; exit 1; }

# Step 5: Download config file
echo "Downloading configuration file..."
CONFIG_URL="https://raw.githubusercontent.com/zstake-xyz/test/main/0g_storage_config.toml"
mkdir -p $HOME/0g-storage-node/run
wget -O $HOME/0g-storage-node/run/0g_storage_config.toml $CONFIG_URL || { echo -e "\033[31mFailed to download config file.\033[0m"; exit 1; }

# Step 6: Set miner key and RPC endpoint
echo "Setting miner key and RPC endpoint..."
# Properly escape special characters for sed
ESCAPED_KEY=$(printf '%s\n' "$PRIVATE_KEY" | sed -e 's/[\/&]/\\&/g')
ESCAPED_ENDPOINT=$(printf '%s\n' "$RPC_ENDPOINT" | sed -e 's/[\/&]/\\&/g')

# Update config file with proper values
sed -i "s|^#*\s*miner_key\s*=.*|miner_key = \"$ESCAPED_KEY\"|" $HOME/0g-storage-node/run/0g_storage_config.toml
sed -i "s|^blockchain_rpc_endpoint\s*=.*|blockchain_rpc_endpoint = \"$ESCAPED_ENDPOINT\"|" $HOME/0g-storage-node/run/c0g_storage_config.toml

echo -e "\033[32mPrivate key and RPC endpoint have been successfully added to the config file.\033[0m"

# Step 7: Verify configuration
echo "Verifying configuration changes..."
grep -E "^(miner_key|blockchain_rpc_endpoint)" $HOME/0g-storage-node/run/0g_storage_config.toml

# Step 8: Configure firewall
echo "Configuring firewall..."
sudo ufw allow 9081:9083/tcp
sudo ufw allow 9081:9083/udp
sudo ufw reload

# Step 9: Create systemd service
echo "Creating systemd service..."
sudo tee /etc/systemd/system/zgs.service > /dev/null <<EOF
[Unit]
Description=ZGS Node
After=network.target

[Service]
User=$USER
WorkingDirectory=$HOME/0g-storage-node/run
ExecStart=$HOME/0g-storage-node/target/release/zgs_node --config $HOME/0g-storage-node/run/0g_storage_config.toml
Restart=on-failure
RestartSec=10
LimitNOFILE=65535

[Install]
WantedBy=multi-user.target
EOF

# Step 10: Start node
echo "Starting node..."
sudo systemctl daemon-reload
sudo systemctl enable zgs
sudo systemctl restart zgs

# Wait for service to start
sleep 5

# Check service status
SERVICE_STATUS=$(sudo systemctl status zgs)
echo "$SERVICE_STATUS"

if [[ "$SERVICE_STATUS" != *"active (running)"* ]]; then
    echo -e "\033[31mError: Service failed to start. Trying to run manually for debugging...\033[0m"
    cd $HOME/0g-storage-node/run
    RUST_LOG=debug RUST_BACKTRACE=full $HOME/0g-storage-node/target/release/zgs_node --config 0g_storage_config.toml
    exit 1
fi

# Step 11: Verify node operation
echo "Verifying node operation..."
sleep 10
curl -s http://localhost:9081/health | jq

# Step 12: Display log command
echo -e "\033[32m\nSetup complete!\033[0m"
echo -e "To check node status:   sudo systemctl status zgs"
echo -e "To view logs:           sudo journalctl -u zgs -f --no-hostname -o cat"
echo -e "To check sync status:   curl -s http://localhost:9081/health | jq"
