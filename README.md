# Vattelum Registry — On-Chain Document Registry

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)
[![Solidity](https://img.shields.io/badge/Solidity-0.8.29-363636.svg)](https://soliditylang.org)
[![Foundry Tests](https://img.shields.io/badge/Foundry_Tests-40_passing-brightgreen.svg)](https://getfoundry.sh)
[![SvelteKit](https://img.shields.io/badge/SvelteKit-Frontend-FF3E00.svg)](https://kit.svelte.dev)

The Registry offers anyone the opportunity to create and store law on the blockchain.

The Registry gives any person or organization a tool to draft, publish, and permanently record laws, standards, governance frameworks, rights declarations, for others to adopt.

Every document follows a standardized format, making it interoperable across the ecosystem. The result will be a growing network of bottom-up legislation that anyone can reference, build on, and adopt as binding to their voluntary interactions.

Part of the [Vattelum](https://github.com/vattelum) ecosystem.

## Demo

https://github.com/user-attachments/assets/registry.mp4

## How It Works

The Registry is run by a single admin.

One wallet deploys the contract, manages categories, and registers documents. Later products will include voting and decentralized decision making.

The Registry combines two pieces of blockchain infrastructure:

1. **Permanent storage** — Documents are uploaded to **Arweave**, where they cannot be changed or deleted. Each upload produces a transaction ID that serves as a permanent link to the full text.

2. **On-chain registry** — A smart contract on **Ethereum** records the Arweave transaction ID, a SHA-256 content hash, title, category, version number, and timestamp for each document. This creates a verifiable index of all registered legislation.

The result is a legislative registry where every document is permanent, every record is independently verifiable, and any other contract or application can reference registered documents by category and version.

Any person can independently verify that a document is authentic and unmodified by fetching it from Arweave, hashing its contents, and comparing the result to the on-chain record.

## Features

- **Document types** — Each document is classified as Original, Amendment, Revision, Repeal, or Codification, creating a clear legislative lifecycle.
- **Section-level targeting** — Amendments and repeals can target specific sections of an existing document, not just the document as a whole.
- **External references** — Documents can link to other on-chain documents, creating a verifiable reference graph across the registry.
- **Three editor modes** — The editor supports normal drafting, amendment mode (for modifying existing documents), and repeal mode (for striking sections).
- **Relationship tags** — The homepage displays document relationships (amends, repeals, revises, codifies), showing the full lifecycle of each piece of legislation.

## Architecture

**Smart Contract** (Solidity 0.8.29, OpenZeppelin 5.x):
- `Registry.sol` — Append-only document registry with categories, versioning, and transferable admin control

**Frontend** (SvelteKit, Tailwind CSS):
- `/` — Public registry browser. Loads categories and documents from the contract, fetches full text from Arweave on demand.
- `/propose` — Structured markdown editor with section numbering (§1, §1.1, §1.1.A), three editing modes (normal, amendment, repeal), Arweave upload, and on-chain registration. Admin-gated.

**External Services**:
- [Arweave](https://arweave.org) — Permanent document storage via [ArDrive Turbo](https://ardrive.io)

## Quick Start

### Browse the demo

The repository ships with a live demo registry on Sepolia testnet. To see it
in action:

1. Clone the repository
2. Copy `.env.example` to `.env` in `apps/frontend/`
3. Run `npm install && npm run dev`
4. Open the app in your browser — the registry loads with example legislation you can browse immediately

### Deploy your own

To create your own registry and register your own documents you must deploy a new smart contract and update the frontend with the contract address.

You are free to select your own categories of legislation you wish to include in your Registry.

#### Prerequisites

- [Node.js](https://nodejs.org) 18+
- [Foundry](https://getfoundry.sh) (for contract compilation, testing, and deployment)
- An Ethereum wallet (MetaMask, Ledger, etc.)


#### 1. Deploy the contract

The contract can be deployed to any EVM-compatible network (Ethereum, Arbitrum, Base, Sepolia, etc.).

```sh
cd apps/contracts
forge install
forge build
forge test
```

Configure your deployment environment and deploy using Foundry.

The deployment script (`script/Deploy.s.sol`) deploys the registry and seeds starter document categories. Edit the script to customize the category names for your use case before deploying.

#### 2. Configure and run frontend

```sh
cd apps/frontend
npm install
cp .env.example .env
```

Edit `.env` with your deployed contract address, chain ID, and RPC URL.

```sh
npm run dev
```

Connect with the deployer wallet to access admin functions (registering documents, managing categories).

### Arweave Setup and Document Registration

The Registry uses [ArDrive Turbo](https://ardrive.io) to upload documents to Arweave. As a result, you can simply connect with the same metamask (or similar) admin account. No separate Arweave wallet or AR tokens are required.

ArDrive Turbo offers a 100 KiB free tier. So it is possible that you do not have to pay anything to store your initial legislation.

The full document storage requires THREE signatures from your wallet:

1. **Connect signature** — A one-time wallet signature to authenticate with the Turbo service (once per session).
2. **Arweave upload** — The wallet signs the data item for permanent storage on Arweave.
3. **On-chain registration** — A standard Ethereum transaction to record the document in the registry contract.

If you upload large-sized or a large amount of documents, your transaction might be refused pending the funding of your account.

1. Go to [app.ardrive.io](https://app.ardrive.io) and connect your Ethereum wallet
2. Purchase Turbo credits using ETH (a small amount covers many documents)

Payments can be made in ETH.

## Configuration

If you deploy your own smart contract, you must update two files to correctly point the Registry to it.

### Contracts `.env`

| Variable | Description |
|---|---|
| `SEPOLIA_RPC_URL` | RPC endpoint for your target network |
| `PRIVATE_KEY` | Deployer wallet private key if you are using the script to upload your smart contract to the testnet (WARNING: storing private keys in an .env file results in a security risk (especially on mainnet). See `.env.example` for safer alternatives) |

### Frontend `.env`

| Variable | Description |
|---|---|
| `VITE_REGISTRY_ADDRESS` | Deployed Registry contract address |
| `VITE_CHAIN_ID` | Chain ID of your target network |
| `VITE_RPC_URL` | RPC endpoint |

## License

MIT
