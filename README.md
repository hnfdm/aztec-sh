<h3 align=center>Aztec Sequencer - Node</h3>

Aztec is building a decentralized, privacy-focused network and the sequencer node is a key part of it. Running a sequencer helps produce and propose blocks using regular consumer hardware. This guide will walk you through setting one up on the testnet.

**Note : There’s no official confirmation of any rewards, airdrop, or incentives. This is purely for learning, contribution and being early in a cutting-edge privacy project.**

### 💻 System Requirements

| Component      | Specification               |
|----------------|-----------------------------|
| CPU            | 8-Core Processor            |
| RAM            | 16 GiB                      |
| Storage        | 1 TB SSD                    |
| Internet Speed | 25 Mbps Upload / Download   |

### ⚙️ Prerequisites
- You can use [Alchemy](https://dashboard.alchemy.com/apps) or [DRPC]([https://drpc.org?ref=3b651d]) to get Sepolia Ethereum RPC.
- You can use [Chainstack](https://chainstack.com/global-nodes) to get the Consensus URL (Beacon RPC URL).
- Create a new evm wallet and fund it with at least 2 Sepolia ETH if you want to register as Validator.

### 📥 Installation

```
curl -O https://raw.githubusercontent.com/hnfdm/sh/main/aztec-sequencer.sh && chmod +x aztec-sequencer.sh && ./aztec-sequencer.sh
```

### 🧩 Post-Installation

**After running node, you should wait at least 10 to 20 mins before your run these commands**

- Use this command to get `block-number`
```
curl -s -X POST -H 'Content-Type: application/json' -d '{"jsonrpc":"2.0","method":"node_getL2Tips","params":[],"id":67}' http://localhost:8080 | jq -r '.result.proven.number'
```
- After running this code, you will get a block number like this : 66666

- Use that block number in the places of `block-number` in the below command to get `proof`

```
curl -s -X POST -H 'Content-Type: application/json' -d '{"jsonrpc":"2.0","method":"node_getArchiveSiblingPath","params":["block-number","block-number"],"id":67}' http://localhost:8080 | jq -r ".result"
```

- Now navigate to `operators | start-here` channel in [Aztec Discord Server](https://discord.com/invite/aztec)
- Use the following command to get `Apprentice` role
```
/operator start
```
- It will ask the `address` , `block-number` and `proof` , Enter all of them one by one and you will get `Apprentice` instantly

### 🚀 Register as Validator

- Replace `SEPOLIA-RPC-URL` , `YOUR-PRIVATE-KEY` , `YOUR-VALIDATOR-ADDRESS` with actual value and then execute this command
```
aztec add-l1-validator \
  --l1-rpc-urls SEPOLIA-RPC-URL \
  --private-key YOUR-PRIVATE-KEY \
  --attester YOUR-VALIDATOR-ADDRESS \
  --proposer-eoa YOUR-VALIDATOR-ADDRESS \
  --staking-asset-handler 0xF739D03e98e23A7B65940848aBA8921fF3bAc4b2 \
  --l1-chain-id 11155111
```

You may see an error like `ValidatorQuotaFilledUntil` when trying to register as a validator, which means the daily quota has been reached—convert the provided Unix timestamp to local time to know when you can try again to register as Validator.
