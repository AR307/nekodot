import { execFileSync, spawn } from 'node:child_process';
import { resolve } from 'node:path';
import { setTimeout as delay } from 'node:timers/promises';

const sdk = process.env.ANDROID_HOME ?? resolve(process.env.LOCALAPPDATA, 'Android/Sdk');
const adb = resolve(sdk, 'platform-tools', 'adb.exe');
const emulator = resolve(sdk, 'emulator', 'emulator.exe');
const avd = 'NekodotNativePhase3';
const runAdb = (...args) => execFileSync(adb, args, { encoding: 'utf8', windowsHide: true }).trim();
const findDevice = () => {
  const serials = runAdb('devices').match(/^emulator-\d+(?=\s+device\b)/gm) ?? [];
  return serials.find(
    (serial) => runAdb('-s', serial, 'emu', 'avd', 'name').split(/\r?\n/)[0].trim() === avd,
  );
};

if (process.platform !== 'win32') throw new Error('Run this project emulator from Windows.');
let device = findDevice();
if (!device) {
  const installed = execFileSync(emulator, ['-list-avds'], { encoding: 'utf8', windowsHide: true });
  if (!installed.split(/\r?\n/).includes(avd))
    throw new Error(`The retained ${avd} AVD is missing. Restore it; do not create another AVD.`);
  const child = spawn(emulator, ['-avd', avd, '-no-boot-anim'], {
    detached: true,
    stdio: 'ignore',
    windowsHide: true,
  });
  child.unref();
}
for (let attempt = 0; attempt < 300; attempt++) {
  device = findDevice();
  if (device && runAdb('-s', device, 'shell', 'getprop', 'sys.boot_completed') === '1') break;
  await delay(1000);
}
if (!device || runAdb('-s', device, 'shell', 'getprop', 'sys.boot_completed') !== '1')
  throw new Error(
    `${avd} has not finished booting. Check this AVD rather than creating a new one.`,
  );
console.log(`Reusing ${avd}: ${device}`);
