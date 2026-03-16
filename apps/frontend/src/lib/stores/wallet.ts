import { writable, derived } from 'svelte/store';

interface WalletState {
	address: `0x${string}` | null;
	connected: boolean;
	connecting: boolean;
	isAdmin: boolean;
}

export const wallet = writable<WalletState>({
	address: null,
	connected: false,
	connecting: false,
	isAdmin: false
});

export const isConnected = derived(wallet, ($w) => $w.connected);
export const walletAddress = derived(wallet, ($w) => $w.address);
export const isAdmin = derived(wallet, ($w) => $w.isAdmin);
