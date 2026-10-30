import { readFile, readdir } from 'node:fs/promises';
import { isAbsolute, resolve, sep } from 'node:path';
import { lookup } from 'mime-types';
import { parse } from 'yaml';
import type { HermesManagement } from './hermes/management';
import { NodeFault } from './fault';

type NativeRow = Record<string, unknown>;

export function documentMetadata(text: string, filename = 'SKILL.md'): NativeRow {
  const raw = filename === 'SKILL.md' ? /^---\r?\n([\s\S]*?)\r?\n---/.exec(text)?.[1] : text;
  return raw ? ((filename.endsWith('.json') ? JSON.parse(raw) : parse(raw)) ?? {}) : {};
}

export function repositoryUrl(value: unknown): string | undefined {
  if (typeof value !== 'string' || !value) return;
  if (/^[\w.-]+\/[\w.-]+$/.test(value)) return 'https://github.com/' + value;
  if (value.startsWith('https://')) return value;
}

/** Presentation metadata only. Installation/enabling remains owned by Hermes. */
export async function localExtensionMetadata(directory: string) {
  const files = await readdir(directory);
  const manifest = files.find((name) =>
    ['plugin.yaml', 'plugin.json', 'hermes.plugin.json', 'SKILL.md'].includes(name),
  );
  let metadata: NativeRow = {};
  if (manifest) {
    const text = await readFile(resolve(directory, manifest), 'utf8');
    metadata = documentMetadata(text, manifest);
  }
  let icon = typeof metadata.icon === 'string' ? metadata.icon : undefined;
  if (icon && !/^(?:https:|data:image\/)/.test(icon) && /\.(?:png|svg|jpe?g|webp)$/i.test(icon)) {
    const path = resolve(directory, icon);
    icon =
      isAbsolute(icon) || !path.startsWith(resolve(directory) + sep)
        ? undefined
        : await readFile(path).then(
            (bytes) => `data:${lookup(path)};base64,${bytes.toString('base64')}`,
            () => undefined,
          );
  }
  return {
    icon,
    repository: repositoryUrl(metadata.repository ?? metadata.repo),
  };
}

export async function pluginDocument(
  management: HermesManagement,
  profile: string,
  installed: NativeRow | undefined,
  catalog: NativeRow | undefined,
) {
  if (installed?.install_dir) {
    const directory = String(installed.install_dir);
    const listing = await management.request<{
      entries: { name: string; path: string; isDirectory: boolean }[];
      error?: string;
    }>('/api/fs/list?path=' + encodeURIComponent(directory), profile);
    if (listing.error) throw new NodeFault('unavailable', 'Plugin directory: ' + listing.error);
    const readme = listing.entries.find((file) => /^readme(?:\.md|\.txt)?$/i.test(file.name));
    const document = readme
      ? await management.request<{ text: string }>(
          '/api/fs/read-text?path=' + encodeURIComponent(readme.path),
          profile,
        )
      : undefined;
    return {
      content: document?.text ?? '',
      files: listing.entries.map((file) => file.name + (file.isDirectory ? '/' : '')),
      ...(await localExtensionMetadata(directory)),
    };
  }
  const repository = repositoryUrl(catalog?.repo);
  if (!repository) return { content: '', files: [] as string[] };
  const url = new URL(repository);
  if (url.hostname !== 'github.com') return { content: '', files: [], repository };
  const [owner, name] = url.pathname.split('/').filter(Boolean);
  const subdir = typeof catalog?.subdir === 'string' ? catalog.subdir : '';
  const response = await fetch(
    `https://api.github.com/repos/${encodeURIComponent(owner!)}/${encodeURIComponent(name!.replace(/\.git$/, ''))}/contents/${subdir.split('/').map(encodeURIComponent).join('/')}`,
    { headers: { Accept: 'application/vnd.github+json' }, signal: AbortSignal.timeout(20_000) },
  );
  if (!response.ok)
    throw new NodeFault('unavailable', `Repository documentation HTTP ${response.status}`);
  const files = (await response.json()) as {
    name: string;
    type: string;
    download_url: string | null;
  }[];
  const readme = files.find((file) => /^readme(?:\.md|\.txt)?$/i.test(file.name));
  let content = '';
  if (readme?.download_url) {
    const document = await fetch(readme.download_url, { signal: AbortSignal.timeout(20_000) });
    if (!document.ok)
      throw new NodeFault('unavailable', `Repository README HTTP ${document.status}`);
    content = await document.text();
  }
  return {
    content,
    files: files.map((file) => file.name + (file.type === 'dir' ? '/' : '')),
    repository,
  };
}
