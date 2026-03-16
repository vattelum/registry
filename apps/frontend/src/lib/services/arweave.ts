import { signMessage, sendTransaction, getConnectorClient } from '@wagmi/core';
import { config } from '$lib/services/ethereum';

// eslint-disable-next-line @typescript-eslint/no-explicit-any
let turbo: any = null;

async function getTurbo() {
	if (!turbo) {
		const client = await getConnectorClient(config);
		if (!client?.account) throw new Error('Wallet not connected');

		const { TurboFactory } = await import('@ardrive/turbo-sdk/web');
		turbo = TurboFactory.authenticated({
			walletAdapter: {
				getSigner: () => ({
					signMessage: (msg: string | Uint8Array) => {
						if (typeof msg === 'string') {
							return signMessage(config, { message: msg });
						}
						return signMessage(config, { message: { raw: msg } });
					},
					// eslint-disable-next-line @typescript-eslint/no-explicit-any
					sendTransaction: (tx: any) => sendTransaction(config, tx),
					provider: client.transport
				})
			},
			token: 'ethereum'
		});
	}
	return turbo;
}

export interface UploadCost {
	winc: string;
	bytes: number;
}

export async function getUploadCost(byteCount: number): Promise<UploadCost> {
	const client = await getTurbo();
	const [cost] = await client.getUploadCosts({ bytes: [byteCount] });
	return { winc: cost.winc, bytes: byteCount };
}

export async function getBalance(): Promise<string> {
	const client = await getTurbo();
	const { winc } = await client.getBalance();
	return winc;
}

export async function uploadDocument(content: string): Promise<string> {
	const client = await getTurbo();
	const result = await client.upload({
		data: content,
		dataItemOpts: {
			tags: [
				{ name: 'Content-Type', value: 'text/markdown' },
				{ name: 'App-Name', value: 'Solon' }
			]
		}
	});
	return result.id;
}

// Reset cached turbo client (call on wallet disconnect/switch)
export function resetTurbo() {
	turbo = null;
}

const GATEWAYS = ['https://arweave.net', 'https://ar-io.dev'];

export function arweaveUrl(txId: string): string {
	return `${GATEWAYS[0]}/${txId}`;
}

const CACHE_PREFIX = 'registry:arweave:';

export async function fetchFromArweave(txId: string, contentHash?: string): Promise<string> {
	// Check localStorage cache by content hash (immutable — never stale)
	if (contentHash) {
		try {
			const cached = localStorage.getItem(CACHE_PREFIX + contentHash);
			if (cached) return cached;
		} catch {
			// storage unavailable
		}
	}

	for (const gateway of GATEWAYS) {
		try {
			const res = await fetch(`${gateway}/${txId}`);
			if (res.ok) {
				const text = await res.text();
				// Cache by content hash — same hash always means same content
				if (contentHash) {
					try {
						localStorage.setItem(CACHE_PREFIX + contentHash, text);
					} catch {
						// storage full — evict oldest entries
						evictOldestCache();
						try {
							localStorage.setItem(CACHE_PREFIX + contentHash, text);
						} catch {
							// still full, skip caching
						}
					}
				}
				return text;
			}
		} catch {
			// try next gateway
		}
	}
	throw new Error('Document not yet available. It may still be confirming on the Arweave network.');
}

function evictOldestCache() {
	const keys: string[] = [];
	for (let i = 0; i < localStorage.length; i++) {
		const key = localStorage.key(i);
		if (key?.startsWith(CACHE_PREFIX)) keys.push(key);
	}
	// Remove first 5 entries to free space
	for (const key of keys.slice(0, 5)) {
		localStorage.removeItem(key);
	}
}
