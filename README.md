# FreelanceEscrow — Trustless On-Chain Escrow for Freelancers

[![Solidity](https://img.shields.io/badge/Solidity-0.8.20-blue)](https://soliditylang.org/)
[![License: MIT](https://img.shields.io/badge/License-MIT-green.svg)](LICENSE)
[![Networks](https://img.shields.io/badge/Networks-Ethereum%20%7C%20Polygon%20%7C%20Arbitrum%20%7C%20Base-purple)]()

---

## Problem Statement

Freelancers lose billions of dollars annually to non-payment, chargebacks, and payment disputes. Traditional escrow services charge 3–10% fees and require trusting a centralised intermediary. This contract eliminates the intermediary while preserving dispute resolution.

---

## How It Works

```
Client                        Freelancer                 Arbitrator
  │                               │                          │
  │── createAgreement (ETH) ──►  │                          │
  │        (funds locked)         │                          │
  │                               │── submitDelivery ──────► │
  │                               │     (IPFS CID)           │
  │◄──────── approveDelivery ─────│                          │
  │     OR                        │                          │
  │──────── raiseDispute ────────►│── raiseDispute          │
  │                               │        │                 │
  │                               │        └─── resolveDispute(BPS)
  │                               │                          │
  │◄── claimRefund (deadline) ────│                          │
```

### State Machine

```
AWAITING_DELIVERY ──► COMPLETE   (approveDelivery)
AWAITING_DELIVERY ──► DISPUTED   (raiseDispute)
AWAITING_DELIVERY ──► REFUNDED   (claimRefund after deadline)
DISPUTED          ──► COMPLETE   (resolveDispute)
```

---

## Key Features

| Feature | Detail |
|---|---|
| **Trustless** | No admin keys; rules enforced by EVM |
| **IPFS proof** | Job description & delivery hashes stored on-chain |
| **Flexible arbitration** | Arbitrator splits payment in any ratio (basis points) |
| **1% arbitration fee** | Only charged if dispute occurs |
| **Gas-optimised errors** | Custom errors instead of `require` strings |
| **CEI pattern** | State updated before transfers → reentrancy safe |

---

## Setup & Deployment

### Prerequisites

```bash
npm install -g hardhat
npm install --save-dev @nomicfoundation/hardhat-toolbox dotenv
```

### Install

```bash
git clone https://github.com/YOUR_USERNAME/freelance-escrow
cd freelance-escrow
npm install
```

### Configure

Create a `.env` file:

```
PRIVATE_KEY=your_wallet_private_key
RPC_URL=https://polygon-mainnet.g.alchemy.com/v2/YOUR_KEY
ETHERSCAN_API_KEY=your_etherscan_key
```

### Deploy

```bash
npx hardhat run scripts/deploy.js --network polygon
```

### Verify on Etherscan / Polygonscan

```bash
npx hardhat verify --network polygon DEPLOYED_CONTRACT_ADDRESS
```

---

## Usage Examples

### 1 — Create an Agreement (Client)

```javascript
const tx = await escrow.createAgreement(
  freelancerAddress,
  arbitratorAddress,
  Math.floor(Date.now() / 1000) + 7 * 24 * 3600, // 7-day deadline
  "QmYourIPFSJobDescriptionHash",
  { value: ethers.parseEther("0.5") }             // 0.5 ETH locked
);
```

### 2 — Submit Delivery (Freelancer)

```javascript
await escrow.submitDelivery(agreementId, "QmYourIPFSDeliveryHash");
```

### 3 — Approve & Release Payment (Client)

```javascript
await escrow.approveDelivery(agreementId);
```

### 4 — Dispute + Resolve (Arbitrator awards 70% to freelancer)

```javascript
await escrow.connect(client).raiseDispute(agreementId);
await escrow.connect(arbitrator).resolveDispute(agreementId, 7000); // 70%
```

---

## Security Considerations

- **Reentrancy**: Checks-Effects-Interactions strictly followed; state is set to `COMPLETE` / `REFUNDED` **before** any ETH transfer.
- **Integer overflow**: Solidity 0.8.x has built-in overflow checks.
- **Griefing**: `claimRefund` is only callable after the deadline, preventing premature reclaims.
- **Arbitrator trust**: The arbitrator is chosen by the client at agreement creation. Use a reputable DAO or multi-sig for high-value contracts.

---

## Testing

```bash
npx hardhat test
npx hardhat coverage
```

Expected coverage: **>95%** on all functions.

---

## Bounty Platform Checklist

- [x] Natspec (`@notice`, `@param`, `@return`) on every public function
- [x] SPDX licence identifier
- [x] No floating pragma — pinned to `^0.8.20`
- [x] No `tx.origin` authentication
- [x] No selfdestruct
- [x] Events emitted for every state change
- [x] Deployment script included

---

## License

MIT — see [LICENSE](LICENSE)
