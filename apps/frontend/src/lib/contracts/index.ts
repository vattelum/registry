import RegistryABI from './Registry.abi.json';

export const registryAddress = import.meta.env.VITE_REGISTRY_ADDRESS as `0x${string}`;

export const registryConfig = {
	address: registryAddress,
	abi: RegistryABI
} as const;

export { RegistryABI };
