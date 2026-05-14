import { readContract } from '@wagmi/core';
import { config } from '$lib/services/wallet-config';
import { registryConfig, RegistryABI } from '$lib/contracts';
import { fetchFromArweave } from '$lib/services/arweave';
import { stripFrontmatter } from '$lib/services/format';
import { markdownToSections, type Section } from '$lib/services/markdown';
import {
	parseVariableSchema,
	type TemplateVariable
} from '$lib/services/template-variables';

export interface CategoryInfo {
	id: number;
	name: string;
	documentCount: number;
}

export interface DocumentInfo {
	categoryId: number;
	documentId: number;
	versionCount: number;
	latestTitle: string;
	/** On-chain amendment restrictions for this document. Fetched in the same
	 *  parallel batch as title/versionCount, so no extra round-trip. */
	restrictions: {
		minTimeBetweenAmendments: number;
		lastAmendmentTime: number;
		lockedSections: number[];
	};
}

export async function loadCategories(): Promise<CategoryInfo[]> {
	const count = (await readContract(config, {
		...registryConfig,
		functionName: 'categoryCount'
	})) as bigint;

	const cats: CategoryInfo[] = [];
	for (let i = 0n; i < count; i++) {
		const [name, docCount] = await Promise.all([
			readContract(config, {
				...registryConfig,
				functionName: 'categoryNames',
				args: [i]
			}),
			readContract(config, {
				...registryConfig,
				functionName: 'getDocumentCount',
				args: [i]
			})
		]);
		cats.push({
			id: Number(i),
			name: name as string,
			documentCount: Number(docCount as bigint)
		});
	}
	return cats;
}

export async function loadDocuments(categoryId: number): Promise<DocumentInfo[]> {
	const docCount = (await readContract(config, {
		...registryConfig,
		functionName: 'getDocumentCount',
		args: [BigInt(categoryId)]
	})) as bigint;

	const docs: DocumentInfo[] = [];
	for (let i = 1n; i <= docCount; i++) {
		const [versionCount, original, restrictionsRaw] = await Promise.all([
			readContract(config, {
				...registryConfig,
				functionName: 'getVersionCount',
				args: [BigInt(categoryId), i]
			}) as Promise<bigint>,
			readContract(config, {
				...registryConfig,
				functionName: 'getDocument',
				args: [BigInt(categoryId), i, 1n]
			}) as Promise<{ title: string }>,
			readContract(config, {
				...registryConfig,
				functionName: 'getAmendmentRestrictions',
				args: [BigInt(categoryId), i]
			}) as Promise<readonly [bigint, bigint, readonly bigint[]]>
		]);
		docs.push({
			categoryId,
			documentId: Number(i),
			versionCount: Number(versionCount),
			latestTitle: original.title,
			restrictions: {
				minTimeBetweenAmendments: Number(restrictionsRaw[0]),
				lastAmendmentTime: Number(restrictionsRaw[1]),
				lockedSections: restrictionsRaw[2].map(Number)
			}
		});
	}
	return docs;
}

export async function getDocumentCount(categoryId: number): Promise<number> {
	const count = (await readContract(config, {
		...registryConfig,
		functionName: 'getDocumentCount',
		args: [BigInt(categoryId)]
	})) as bigint;
	return Number(count);
}

/**
 * Load categories from any registry that implements the standard interface (Referencing Standard §3.3).
 * Uses the DAARegistry ABI — all Vattelum registries share the same contract interface.
 */
export async function loadCategoriesFrom(registryAddress: `0x${string}`): Promise<CategoryInfo[]> {
	const extConfig = { address: registryAddress, abi: RegistryABI } as const;
	const count = (await readContract(config, {
		...extConfig,
		functionName: 'categoryCount'
	})) as bigint;

	const cats: CategoryInfo[] = [];
	for (let i = 0n; i < count; i++) {
		const [name, docCount] = await Promise.all([
			readContract(config, { ...extConfig, functionName: 'categoryNames', args: [i] }),
			readContract(config, { ...extConfig, functionName: 'getDocumentCount', args: [i] })
		]);
		cats.push({ id: Number(i), name: name as string, documentCount: Number(docCount as bigint) });
	}
	return cats;
}

/**
 * Load documents from any registry that implements the standard interface.
 */
export async function loadDocumentsFrom(registryAddress: `0x${string}`, categoryId: number): Promise<DocumentInfo[]> {
	const extConfig = { address: registryAddress, abi: RegistryABI } as const;
	const docCount = (await readContract(config, {
		...extConfig,
		functionName: 'getDocumentCount',
		args: [BigInt(categoryId)]
	})) as bigint;

	const docs: DocumentInfo[] = [];
	for (let i = 1n; i <= docCount; i++) {
		const [versionCount, original] = await Promise.all([
			readContract(config, { ...extConfig, functionName: 'getVersionCount', args: [BigInt(categoryId), i] }) as Promise<bigint>,
			readContract(config, { ...extConfig, functionName: 'getDocument', args: [BigInt(categoryId), i, 1n] }) as Promise<{ title: string }>
		]);
		docs.push({
			categoryId,
			documentId: Number(i),
			versionCount: Number(versionCount),
			latestTitle: original.title,
			// Cross-registry: we don't read lock state from foreign registries,
			// and the homepage doesn't render lock badges for them. Empty
			// restrictions matches that runtime contract.
			restrictions: { minTimeBetweenAmendments: 0, lastAmendmentTime: 0, lockedSections: [] }
		});
	}
	return docs;
}

export type LegislationStatus = 'InForce' | 'PartiallyAmended' | 'Repealed';

export interface LegislationPackageInfo {
	categoryId: number;
	documentId: number;
	title: string;
	status: LegislationStatus;
	genesisDocType: number;
	versionCount: number;
	/** For Codifications: the lineages consolidated (CODIFIES references on the genesis). */
	codifies: Array<{ registryAddress: `0x${string}`; categoryId: number; documentId: number }>;
}

/**
 * On-chain document shape per Referencing Standard v6 §3.3. Shared by every
 * registry that implements the v6 interface (Registry, BVSRegistry,
 * DAARegistry). Exported for cross-registry readers and consumers.
 */
export interface RegistryDocument {
	contentUri: string;
	contentHash: `0x${string}`;
	title: string;
	version: bigint;
	timestamp: bigint;
	voteId: string;
	docType: number;
}

/**
 * On-chain reference shape per Referencing Standard v6 §3.1. Identical to the
 * `DocumentReference` exported from `contract-registry.ts` (both match the
 * aligned Solidity struct); kept here for local readability.
 */
export interface RegistryReference {
	registryAddress: `0x${string}`;
	chainId: bigint;
	categoryId: bigint;
	documentId: bigint;
	version: bigint;
	relationType: number;
	targetSection: string;
}

export interface AmendmentRestrictions {
	minTimeBetweenAmendments: number;
	lastAmendmentTime: number;
	lockedSections: number[];
}

import {
	RELATION_CODIFIES,
	RELATION_REPEALS,
	DOC_TYPE_AMENDMENT as DOCTYPE_AMENDMENT,
	DOC_TYPE_REPEAL as DOCTYPE_REPEAL
} from '@vattelum/document-registry-js';

/**
 * Load one legislation package per documentId, enriched with status and genesis
 * metadata. Hides bare amendments/repeals masquerading as their own lineages
 * (genesis docType = 1 or 3) and fully-repealed lineages. Intended for use in
 * the /contract legislation picker.
 *
 * Uses the DAA-local registry by default; pass a different address for external registries.
 */
export async function loadLegislationPackages(
	categoryId: number,
	registryAddress?: `0x${string}`
): Promise<LegislationPackageInfo[]> {
	const cfg = registryAddress
		? ({ address: registryAddress, abi: RegistryABI } as const)
		: registryConfig;

	const docCount = (await readContract(config, {
		...cfg,
		functionName: 'getDocumentCount',
		args: [BigInt(categoryId)]
	})) as bigint;

	const packages: LegislationPackageInfo[] = [];
	for (let i = 1n; i <= docCount; i++) {
		const history = (await readContract(config, {
			...cfg,
			functionName: 'getHistory',
			args: [BigInt(categoryId), i]
		})) as readonly RegistryDocument[];

		if (history.length === 0) continue;
		const genesis = history[0];

		// Hide bare Amendment or bare Repeal lineages (malformed but defensive).
		if (genesis.docType === DOCTYPE_AMENDMENT || genesis.docType === DOCTYPE_REPEAL) continue;

		// Determine status from the history.
		let status: LegislationStatus = 'InForce';
		let wholelyRepealed = false;

		if (history.length > 1) {
			status = 'PartiallyAmended';
			for (let j = 1; j < history.length; j++) {
				const v = history[j];
				if (v.docType !== DOCTYPE_REPEAL) continue;
				const refs = (await readContract(config, {
					...cfg,
					functionName: 'getReferences',
					args: [BigInt(categoryId), i, v.version]
				})) as readonly RegistryReference[];
				const repealRef = refs.find((r) => r.relationType === RELATION_REPEALS);
				if (repealRef && repealRef.targetSection.trim() === '') {
					wholelyRepealed = true;
					break;
				}
			}
		}

		if (wholelyRepealed) continue; // hide wholly-repealed lineages

		// Resolve codifies list from the genesis references.
		let codifies: LegislationPackageInfo['codifies'] = [];
		try {
			const genesisRefs = (await readContract(config, {
				...cfg,
				functionName: 'getReferences',
				args: [BigInt(categoryId), i, 1n]
			})) as readonly RegistryReference[];
			codifies = genesisRefs
				.filter((r) => r.relationType === RELATION_CODIFIES)
				.map((r) => ({
					registryAddress: r.registryAddress,
					categoryId: Number(r.categoryId),
					documentId: Number(r.documentId)
				}));
		} catch {
			codifies = [];
		}

		packages.push({
			categoryId,
			documentId: Number(i),
			title: genesis.title,
			status,
			genesisDocType: genesis.docType,
			versionCount: history.length,
			codifies
		});
	}
	return packages;
}

export interface DocumentBody {
	title: string;
	/** Raw markdown with YAML frontmatter stripped, leading whitespace trimmed. */
	body: string;
	/** Parsed sections from `body` (via markdownToSections). */
	sections: Section[];
	/** Template variables declared in the frontmatter (empty when absent). */
	variables: TemplateVariable[];
	contentUri: string;
	contentHash: `0x${string}`;
	docType: number;
}

/**
 * Fetch one document version by (catId, docId, ver) from the given registry
 * (defaults to the configured Registry), pull its body from Arweave, strip
 * frontmatter, parse sections, and parse any `variables:` block.
 *
 * Pass `version` to fetch a specific version via `getDocument`; omit it to
 * fetch the latest via `getLatest`.
 */
export async function loadDocumentBody(
	categoryId: number,
	documentId: number,
	version?: number,
	registryAddress?: `0x${string}`
): Promise<DocumentBody> {
	const cfg = registryAddress
		? ({ address: registryAddress, abi: RegistryABI } as const)
		: registryConfig;

	const raw = version !== undefined
		? (await readContract(config, {
			...cfg,
			functionName: 'getDocument',
			args: [BigInt(categoryId), BigInt(documentId), BigInt(version)]
		})) as { contentUri: string; contentHash: `0x${string}`; title: string; docType: number; version: bigint }
		: (await readContract(config, {
			...cfg,
			functionName: 'getLatest',
			args: [BigInt(categoryId), BigInt(documentId)]
		})) as { contentUri: string; contentHash: `0x${string}`; title: string; docType: number; version: bigint };

	const text = await fetchFromArweave(raw.contentUri, raw.contentHash);
	const body = stripFrontmatter(text);
	return {
		title: raw.title,
		body,
		sections: markdownToSections(body),
		variables: parseVariableSchema(text),
		contentUri: raw.contentUri,
		contentHash: raw.contentHash,
		docType: raw.docType
	};
}

export async function loadAmendmentRestrictions(categoryId: number, documentId: number) {
	const result = (await readContract(config, {
		...registryConfig,
		functionName: 'getAmendmentRestrictions',
		args: [BigInt(categoryId), BigInt(documentId)]
	})) as [bigint, bigint, bigint[]];

	return {
		minTimeBetweenAmendments: Number(result[0]),
		lastAmendmentTime: Number(result[1]),
		lockedSections: result[2].map(Number)
	};
}
