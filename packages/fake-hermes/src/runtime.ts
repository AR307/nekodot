import { join } from 'node:path';
import { HermesManagement } from '../../../apps/node/src/hermes/management';
import type { HermesRuntime } from '../../../apps/node/src/hermes/runtime';

/** Test injection only; production always constructs ManagedHermes. */
export function recordedManagementRuntime(
  url: string,
  key: string,
  home: string,
  catalog: unknown,
): Pick<HermesRuntime, 'management' | 'profileHome' | 'cli' | 'restart'> {
  return {
    management: new HermesManagement(url, key),
    profileHome: (profile) => join(home, 'profiles', profile),
    cli: async () => JSON.stringify(catalog),
    restart: async () => {},
  };
}
