# Vattelum Registry — On-Chain Law Registry

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)
[![Solidity](https://img.shields.io/badge/Solidity-0.8.31-363636.svg)](https://soliditylang.org)
[![Foundry Tests](https://img.shields.io/badge/Foundry_Tests-44_passing-brightgreen.svg)](https://getfoundry.sh)
[![SvelteKit](https://img.shields.io/badge/SvelteKit-Frontend-FF3E00.svg)](https://kit.svelte.dev)

The Registry offers anyone the opportunity to create and store law on the blockchain.

Draft, publish, and permanently record your own laws, standards, governance frameworks, or rights declarations, for others to adopt!

Every document follows a standardized format, realizing interoperability across the ecosystem.

The result will be a growing network of (bottom-up) legislation that anyone in the indsutry can reference, build on, and adopt as binding to their voluntary interactions.

Part of the [Vattelum](https://github.com/vattelum) ecosystem.

## Demo

https://github.com/user-attachments/assets/2fdb1add-fbcf-48f7-9e87-c300557fb7d6

## How It Works

The Registry is run by a single admin.

One wallet deploys the contract, manages categories, and registers documents.

The Registry combines two pieces of blockchain infrastructure:

1. **Permanent storage** — Documents are uploaded to **Arweave**, where they cannot be changed or deleted. Each upload produces a transaction ID that serves as a permanent link to the full text.

2. **On-chain registry** — A smart contract on **Ethereum** records a storage-agnostic content URI (Arweave by default), a SHA-256 content hash, title, category, document ID, version number, and timestamp for each document. The registry conforms to the `IDocumentRegistry` interface from `@vattelum/document-registry`, so other registries (DAA, BVS, SCB) can cite Registry documents using a shared `(registryAddress, chainId, categoryId, documentId, version)` tuple.

The registry is organised in three layers: **categories** (folders), **documents** (independent entities with their own version chains and document IDs), and **versions** (the append-only history of each document).

Per-document **amendment restrictions** are enforced on-chain. The admin may lock specific sections, set a minimum time between amendments, or both. While a lock is active, nobody can amend the law. After the lock window elapses, the admin regains free access.

The result is a legislative registry where every document is permanent, every record is independently verifiable, and any other contract or application can reference registered documents by category and version.

Any person can independently verify that a document is authentic and unmodified by fetching it from Arweave, hashing its contents, and comparing the result to the on-chain record.

## Features

- **Document types** — Each document is classified as Original, Amendment, Revision, Repeal, or Codification, creating a clear legislative lifecycle.
- **Section-level targeting** — Amendments and repeals can target specific sections of an existing document, not just the document as a whole.
- **External references** — Documents can link to other on-chain documents, creating a verifiable reference graph across the registry.
- **Three editor modes** — The editor supports normal drafting, amendment mode (for modifying existing documents), and repeal mode (for striking sections).
- **Relationship tags** — The homepage displays document relationships (amends, repeals, revises, codifies), showing the full lifecycle of each piece of legislation.

## Architecture

**Smart Contract** (Solidity 0.8.31, OpenZeppelin 5.x):
- `Registry.sol` — Append-only document registry with categories, document layer, versioning, transferable admin control, and on-chain hard-lock amendment restrictions
- Conforms to `IDocumentRegistry` from [`@vattelum/document-registry`](https://github.com/vattelum/document-registry) (Solidity standard, vendored as submodule) — interoperable with other Vattelum registries. Frontend uses the [`@vattelum/document-registry-js`](https://www.npmjs.com/package/@vattelum/document-registry-js) companion package for type definitions and `hashBody`.

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

This package contains a demo registry with documents in three categories.

To create your own registry and register your own documents you must deploy a new smart contract and update the frontend with the contract address.

You are free to select the number of categories of legislation and their names in your Registry. Set these in the deployment script before deploying.

#### Prerequisites

- [Node.js](https://nodejs.org) 20.19+ or 22.12+ (required by Vite 7)
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

If you also enable amendment restrictions on submit, a FOURTH transaction is sent to call `setAmendmentRestrictions` on the freshly recorded document.

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
| `VITE_ADMIN_ADDRESS` | Initial admin wallet address (used for client-side `isAdmin` gating) |
| `VITE_CHAIN_ID` | Chain ID of your target network |
| `VITE_RPC_URL` | RPC endpoint |

## User-Suggested Use Cases

**Dynamic Terms & Conditions** — A website owner can link her website's T&Cs directly to a Registry document. Letting clients adjust selected aspects of the terms and conditions—in this case the licensing of software—increases engagement and feelings of ownership. Since website terms bind visitors through use rather than individual contracts, any website can include dynamic terms for its products with no added legal complexity.

## License

MIT
