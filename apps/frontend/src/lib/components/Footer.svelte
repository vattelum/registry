<script lang="ts">
	import { formatNetwork, explorerAddressUrl } from '$lib/constants/networks';

	const chainId = Number(import.meta.env.VITE_CHAIN_ID);

	const contracts = [
		{ label: 'Registry', address: import.meta.env.VITE_REGISTRY_ADDRESS }
	].filter((c) => c.address && c.address !== '0x') as Array<{
		label: string;
		address: `0x${string}`;
	}>;
</script>

<footer class="border-t border-border mt-12 px-8 py-6 text-xs text-text-muted">
	<div class="max-w-4xl mx-auto flex flex-col gap-2">
		<p class="text-text-secondary">
			Deployed contracts on {formatNetwork(chainId)}
		</p>
		<div class="grid grid-cols-[auto_1fr] gap-x-4 gap-y-1 font-mono">
			{#each contracts as c (c.label)}
				<span class="text-text-secondary">{c.label}</span>
				{#if explorerAddressUrl(chainId, c.address)}
					<a
						href={explorerAddressUrl(chainId, c.address)}
						target="_blank"
						rel="noreferrer"
						class="text-text-muted hover:text-text break-all"
					>{c.address}</a>
				{:else}
					<span class="break-all">{c.address}</span>
				{/if}
			{/each}
		</div>
	</div>
</footer>
