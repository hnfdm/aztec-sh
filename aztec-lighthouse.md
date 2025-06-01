### 📘 Guide: Auto Setup Beacon RPC for Sequencer

This guide walks you through setting up a Beacon Sepolia Ethereum node (Geth + Lighthouse) using an automated script. Ideal for running a sequencer backend that requires both RPC and Beacon API access.

---

### ⚙️ System Requirements

- **Disk:** 1TB+ SSD
- **RAM:** 16GB+
- **OS:** Ubuntu 20.04+ (or compatible Linux distro)
- **Tools:** Docker, Docker Compose, `curl`, `openssl`

---

### 🚀 Setup Instructions

```bash
curl -sL https://raw.githubusercontent.com/hnfdm/aztec-sh/main/aztec-lighthouse.sh -o aztec-lighthouse.sh && chmod +x aztec-lighthouse.sh && bash aztec-lighthouse.sh

```
This will:
- Create folder structure at `~/sepolia-node`
- Generate a valid `jwt.hex`
- Write a production-ready `docker-compose.yml`
- Launch Geth + Lighthouse for Beacon Sepolia

---

### ✅ Verify & Monitor

1️⃣ Check Sync Progress:
```bash
curl -s -X POST -H "Content-Type: application/json" --data '{"jsonrpc":"2.0","method":"eth_syncing","params":[],"id":1}' http://localhost:8545 | jq
```

2️⃣ Check Sync Log:
```bash
docker logs -f geth
```

3️⃣ Check Lighthouse Log:
```bash
 docker logs -f lighthouse
```

4️⃣ Check Beacon API health:
```bash
curl -s http://localhost:5052/eth/v1/node/syncing | jq
```

5️⃣ Monitor Storage:
```bash
watch df -h /root/sepolia-node
```

6️⃣ Auto Prune Log:
```bash
watch df -h /root/sepolia-node
```

---

### 🧠 Notes
- The sync process may take several hours to complete.
- Ensure enough disk space (500GB+) is available.
- Once `eth_syncing` returns `false`, your RPC is fully operational.
- Once opened, you can access RPC or Beacon API from other machines via:
- Geth RPC: `http://<your-ip>:8545`
- Beacon API: `http://<your-ip>:5052`

---

### 🗑️ Remove Node
```bash
cd ~/sepolia-node && docker compose down && rm -rf ~/sepolia-node
```
