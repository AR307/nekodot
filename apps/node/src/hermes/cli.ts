import { spawn, type ChildProcess } from 'node:child_process';
export interface HermesLaunch {
  command: string;
  prefixArgs?: string[];
  home: string;
  runtimeDir: string;
  cwd: string;
}
export function spawnHermesCli(launch: HermesLaunch, args: string[]): ChildProcess {
  return spawn(launch.command, [...(launch.prefixArgs ?? []), ...args], {
    cwd: launch.cwd,
    env: { ...process.env, HERMES_HOME: launch.home, HERMES_RUNTIME_DIR: launch.runtimeDir },
    stdio: ['ignore', 'pipe', 'pipe'],
  });
}
export async function runHermesCli(launch: HermesLaunch, args: string[]): Promise<string> {
  const child = spawnHermesCli(launch, args);
  let output = '';
  child.stdout?.on('data', (chunk: Buffer) => {
    output += chunk.toString();
  });
  child.stderr?.on('data', (chunk: Buffer) => {
    output += chunk.toString();
  });
  await new Promise<void>((resolve, reject) => {
    child.once('error', reject);
    child.once('exit', (code) =>
      code === 0 ? resolve() : reject(new Error('Hermes CLI exited ' + code + ': ' + output)),
    );
  });
  return output;
}
