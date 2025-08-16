# LOST Protocol – Smart Contract Scripts

This repository contains production-ready scripts for deploying, upgrading, testing, verifying, and managing LOST Protocol smart contracts on the Hedera Testnet.

All contracts follow the UUPS proxy pattern using OpenZeppelin Upgrades.

---

## 📦 Available Scripts

### `deploy.js` – Deploy All Contracts  
Deploys all LOST Protocol smart contracts using UUPS upgradeable proxies.

```bash
bun hardhat run scripts/deploy.js --network hedera
````

---

### `upgrade.js` – Upgrade Contracts

Safely upgrades deployed contracts while preserving state.

```bash
bun hardhat run scripts/upgrade.js --network hedera
```

---

### `verify.js` – Verify Contracts

Verifies contract source code on Hedera-compatible explorers.

```bash
bun hardhat run scripts/verify.js --network hedera
```

---

### `test-contracts.js` – Contract Testing

Runs functionality and integration tests against all deployed contracts.

```bash
bun hardhat run scripts/test-contracts.js --network hedera
```

---

### `fund-account.js` – Fund Deployment Wallet

Transfers HBAR to your deployment account for gas usage.

```bash
bun hardhat run scripts/fund-account.js --network hedera
```

---

## ⚙️ Configuration

### Required: `.env` File

```ini
# Required Hedera Config
HEDERA_NETWORK=testnet
HEDERA_OPERATOR_ID=0.0.xxxxxxx
HEDERA_OPERATOR_KEY=<YOUR_PRIVATE_KEY>

# Optional Overrides
USDC_TOKEN_ADDRESS=0x...
NFT_METADATA_BASE_URI=https://your-api.com/metadata/
```

---

## 🧱 Requirements

* [Bun](https://bun.sh)
* [Hardhat](https://hardhat.org)
* OpenZeppelin Upgrades plugin
* Funded Hedera testnet account
* Proper `.env` file

---

## Notes

* All scripts are network-agnostic and configured via environment variables.
* Deployment metadata is saved to `deployment-info.json`.
* Contract verification assumes source code is flattened and matches the deployed bytecode.
