import { isTauri, invoke, addPluginListener } from '@tauri-apps/api/core';

export const native = isTauri();
export const android = native && /Android/i.test(navigator.userAgent);
let active = true;
export const appActive = () => active && document.visibilityState !== 'hidden';

export async function nativeCommand<T>(command: string, args?: Record<string, unknown>) {
  try {
    return await invoke<T>('plugin:nekodot|' + command, args);
  } catch (reason) {
    throw new Error(
      reason && typeof reason === 'object' && 'message' in reason
        ? String(reason.message)
        : String(reason),
      { cause: reason },
    );
  }
}

export async function backgroundApp() {
  if (android) await nativeCommand('background');
}

export async function saveDownload(blob: Blob, name: string) {
  if (native) {
    const { save } = await import('@tauri-apps/plugin-dialog');
    const { writeFile } = await import('@tauri-apps/plugin-fs');
    const path = await save({ defaultPath: name });
    if (path) await writeFile(path, new Uint8Array(await blob.arrayBuffer()));
    return;
  }
  const url = URL.createObjectURL(blob);
  const link = document.createElement('a');
  link.href = url;
  link.download = name;
  link.click();
  window.setTimeout(() => URL.revokeObjectURL(url), 1000);
}
export async function shareFile(blob: Blob, name: string) {
  await nativeCommand('share_file', {
    name,
    mime: blob.type,
    data: Array.from(new Uint8Array(await blob.arrayBuffer())),
  });
}
export async function chooseImportFiles(directory: boolean): Promise<File[]> {
  const { open } = await import('@tauri-apps/plugin-dialog');
  const { readFile, readDir } = await import('@tauri-apps/plugin-fs');
  const { basename } = await import('@tauri-apps/api/path');
  const paths = await open({ directory, multiple: !directory });
  if (!paths) return [];
  const files: File[] = [];
  async function collect(path: string, relative: string) {
    const file = new File([await readFile(path)], relative.split('/').at(-1)!);
    Object.defineProperty(file, 'webkitRelativePath', { value: relative });
    files.push(file);
  }
  if (directory && typeof paths === 'string') {
    async function visit(path: string, relative: string) {
      for (const entry of await readDir(path)) {
        const childPath = `${path}/${entry.name}`;
        const childRelative = `${relative}/${entry.name}`;
        if (entry.isDirectory) await visit(childPath, childRelative);
        else if (entry.isFile) await collect(childPath, childRelative);
      }
    }
    await visit(paths, await basename(paths));
  } else
    for (const path of typeof paths === 'string' ? [paths] : paths)
      await collect(path, await basename(path));
  return files;
}
export async function writeClipboard(text: string) {
  if (native) {
    const { writeText } = await import('@tauri-apps/plugin-clipboard-manager');
    await writeText(text);
  } else await navigator.clipboard.writeText(text);
}
export async function clientLifecycle() {
  if (!native) return () => {};
  const { openUrl } = await import('@tauri-apps/plugin-opener');
  const links = (event: MouseEvent) => {
    const anchor = (event.target as Element).closest('a[href]') as HTMLAnchorElement | null;
    if (anchor && /^https?:/.test(anchor.href) && !anchor.download) {
      event.preventDefault();
      void openUrl(anchor.href);
    }
  };
  document.addEventListener('click', links);
  const visibility = () => {
    if (android) return;
    active = document.visibilityState !== 'hidden';
    window.dispatchEvent(new Event(active ? 'nekodot:resume' : 'nekodot:pause'));
    if (active) window.dispatchEvent(new Event('online'));
  };
  document.addEventListener('visibilitychange', visibility);
  const back = () => {
    const dialog = [...document.querySelectorAll<HTMLElement>('[role="dialog"]')].at(-1);
    const close = dialog?.querySelector<HTMLButtonElement>('header button');
    if (close) close.click();
    else if (dialog) window.dispatchEvent(new KeyboardEvent('keydown', { key: 'Escape' }));
    else window.dispatchEvent(new Event('nekodot:back'));
  };
  const listener = android
    ? await addPluginListener<{ active: boolean }>('nekodot', 'lifecycle', (event) => {
        active = event.active;
        window.dispatchEvent(new Event(active ? 'nekodot:resume' : 'nekodot:pause'));
        if (active) window.dispatchEvent(new Event('online'));
      })
    : undefined;
  const backListener = android ? await addPluginListener('nekodot', 'back', back) : undefined;
  return () => {
    document.removeEventListener('click', links);
    document.removeEventListener('visibilitychange', visibility);
    void listener?.unregister();
    void backListener?.unregister();
  };
}
