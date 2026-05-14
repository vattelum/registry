<script lang="ts">
	import ContentUriLink from '$lib/components/ContentUriLink.svelte';
	import ExplorerLink from '$lib/components/ExplorerLink.svelte';

	export interface RegistrationConfirmationData {
		txHash: `0x${string}`;
		contentUri: string;
		title: string;
		category: string;
		categoryId: number;
		documentId: number;
		version: number;
		docTypeName: string;
		refSummary: string;
		restrictionsTxHash?: `0x${string}`;
	}

	interface Props {
		data: RegistrationConfirmationData;
		chainId: number;
		onReset: () => void;
	}

	let { data, chainId, onReset }: Props = $props();
</script>

<div class="flex flex-col gap-4 border border-border rounded-lg p-5 bg-bg-light">
	<div>
		<p class="text-text-secondary text-sm">Title</p>
		<p class="font-medium">{data.title}</p>
	</div>
	<div class="grid grid-cols-2 gap-4 text-sm">
		<div>
			<p class="text-text-secondary">Category</p>
			<p>{data.category}</p>
		</div>
		<div>
			<p class="text-text-secondary">Type</p>
			<p>{data.docTypeName}</p>
		</div>
		<div>
			<p class="text-text-secondary">Document ID</p>
			<p class="font-mono">{data.documentId}</p>
		</div>
		<div>
			<p class="text-text-secondary">Version</p>
			<p class="font-mono">v{data.version}</p>
		</div>
	</div>
	{#if data.refSummary}
		<div class="text-sm">
			<p class="text-text-secondary">Reference</p>
			<p>{data.refSummary}</p>
		</div>
	{/if}
	<div class="text-sm">
		<p class="text-text-secondary mb-1">Arweave</p>
		<ContentUriLink uri={data.contentUri} />
	</div>
	<div class="text-sm">
		<p class="text-text-secondary mb-1">Transaction</p>
		<ExplorerLink tx={data.txHash} {chainId} />
	</div>
	{#if data.restrictionsTxHash}
		<div class="text-sm">
			<p class="text-text-secondary mb-1">Restrictions transaction</p>
			<ExplorerLink tx={data.restrictionsTxHash} {chainId} />
		</div>
	{/if}
	<div class="flex gap-3 mt-2">
		<a href="/" class="text-primary hover:underline text-sm">View on registry</a>
		<button onclick={onReset} class="text-primary hover:underline text-sm">Draft another</button>
	</div>
</div>
