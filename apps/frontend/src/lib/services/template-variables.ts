/**
 * Parses `variables:` declarations from a document's YAML frontmatter.
 *
 * Consumed by `loadDocumentBody` in `$lib/services/registry`, which surfaces
 * the parsed list to `SectionTargetPicker` so a contributor amending a
 * template can see which variable slots the target document expects.
 */

export interface TemplateVariable {
	name: string;
	label: string;
	type: string;
	required: boolean;
}

/**
 * Parse `variables:` block from document YAML frontmatter.
 * Returns structured variable definitions, or empty array if none found.
 */
export function parseVariableSchema(content: string): TemplateVariable[] {
	const fmMatch = content.match(/^---\n([\s\S]*?)\n---/);
	if (!fmMatch) return [];

	const yamlBlock = fmMatch[1];
	if (!yamlBlock.includes('variables:')) return [];

	// Match the variables block: everything after "variables:" until the next top-level key or end
	const varsMatch = yamlBlock.match(/variables:\n((?:\s+-[\s\S]*?)*)(?=\n\w|\s*$)/);
	if (!varsMatch) return [];

	const entries = varsMatch[1].split(/\n\s*-\s*/).filter(Boolean);

	return entries
		.map((entry) => {
			const nameMatch = entry.match(/name:\s*"?([^"\n,}]+)"?/);
			const labelMatch = entry.match(/label:\s*"?([^"\n,}]+)"?/);
			const typeMatch = entry.match(/type:\s*"?([^"\n,}]+)"?/);
			const reqMatch = entry.match(/required:\s*(true|false)/);

			const name = nameMatch?.[1]?.trim() ?? '';
			// Normalise legacy `type: "string"` to the HTML-input-aligned `'text'`
			// so downstream consumers see one canonical value.
			let type = typeMatch?.[1]?.trim() ?? 'text';
			if (type === 'string') type = 'text';
			return {
				name,
				label: labelMatch?.[1]?.trim() ?? name,
				type,
				required: reqMatch?.[1] === 'true'
			};
		})
		.filter((v) => v.name);
}

/**
 * Returns true if the document content has a `variables:` block in its frontmatter.
 * Used for lightweight detection without full parsing.
 */
export function hasVariableSchema(content: string): boolean {
	const fmMatch = content.match(/^---\n([\s\S]*?)\n---/);
	if (!fmMatch) return false;
	return fmMatch[1].includes('variables:');
}

/**
 * Serialize an array of TemplateVariable into a YAML variables: block
 * suitable for inclusion in document frontmatter.
 */
export function serializeVariableSchema(variables: TemplateVariable[]): string {
	if (variables.length === 0) return '';
	const entries = variables.map((v) =>
		`  - name: "${v.name}"\n    label: "${v.label}"\n    type: "${v.type}"\n    required: ${v.required}`
	).join('\n');
	return `variables:\n${entries}`;
}
