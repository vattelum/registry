import {
	createConfig,
	http,
	connect,
	disconnect,
	reconnect,
	readContract,
	watchAccount,
	getPublicClient
} from '@wagmi/core';
import { sepolia, mainnet } from 'viem/chains';
import { injected } from '@wagmi/connectors';
import { wallet } from '$lib/stores/wallet';
import { registryConfig } from '$lib/contracts';
import { resetTurbo } from '$lib/services/arweave';

const chainId = Number(import.meta.env.VITE_CHAIN_ID);
const rpcUrl = import.meta.env.VITE_RPC_URL as string;

const chain = chainId === 1 ? mainnet : sepolia;

export const config = createConfig({
	chains: [chain],
	connectors: [injected()],
	transports: {
		[chain.id]: http(rpcUrl)
	}
});

watchAccount(config, {
	onChange(account) {
		resetTurbo();
		wallet.set({
			address: account.address ?? null,
			connected: account.isConnected,
			connecting: account.isConnecting,
			isAdmin: false
		});
		if (account.address) {
			checkAdmin(account.address);
		}
	}
});

reconnect(config);

export async function connectWallet() {
	return connect(config, { connector: injected() });
}

export async function disconnectWallet() {
	return disconnect(config);
}

export function getClient() {
	return getPublicClient(config);
}

async function checkAdmin(address: `0x${string}`) {
	try {
		const adminAddress = await readContract(config, {
			...registryConfig,
			functionName: 'admin'
		});
		const isAdmin = address.toLowerCase() === (adminAddress as string).toLowerCase();
		wallet.update((w) => ({ ...w, isAdmin }));
	} catch {
		wallet.update((w) => ({ ...w, isAdmin: false }));
	}
}
