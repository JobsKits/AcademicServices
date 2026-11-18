// Created by Jobs on 2026年11月18日，星期三.
// Builds only an isolated test executable; production sources remain unchanged.
import { spawn } from 'node:child_process';
import { mkdtemp, mkdir, cp, readFile, writeFile } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

if (process.platform !== 'darwin') throw new Error('This Swift/AppKit store fixture requires MacOS and Xcode Command Line Tools.');
const here = path.dirname(fileURLToPath(import.meta.url));
const pc = path.resolve(here, '../../../../代码/前端/PC端');
const work = await mkdtemp(path.join(tmpdir(), 'zhixu-store-concurrency-'));
const contents = path.join(work, 'StoreConcurrency.app/Contents');
await mkdir(path.join(contents, 'MacOS'), { recursive: true });
await mkdir(path.join(contents, 'Resources'));
for (const file of ['shop_strings.json', 'products.json']) await cp(path.join(pc, 'Web/Assets', file), path.join(contents, 'Resources', file));
await writeFile(path.join(contents, 'Info.plist'), '<?xml version="1.0"?><plist version="1.0"><dict><key>CFBundleExecutable</key><string>StoreConcurrency</string><key>CFBundleIdentifier</key><string>com.jobs.ZhixuStoreConcurrency</string></dict></plist>');
// Swap only the transport symbol in an ephemeral copy to control response order.
const source = await readFile(path.join(pc, 'MacOS/Sources/ShopStore.swift'), 'utf8');
const storeCopy = path.join(work, 'ShopStore.swift');
await writeFile(storeCopy, source.replace(/\bNativeAPI\b/g, 'StoreFixtureAPI'));
const run = (command, args) => new Promise((resolve, reject) => {
  const child = spawn(command, args, { stdio: 'inherit' });
  child.on('error', reject);
  child.on('exit', (code, signal) => code === 0 ? resolve() : reject(new Error(`${command} failed (${code ?? signal})`)));
});
const executable = path.join(contents, 'MacOS/StoreConcurrency');
await run('xcrun', ['swiftc', '-swift-version', '5', '-parse-as-library', path.join(pc, 'MacOS/Sources/Models.swift'), path.join(pc, 'MacOS/Sources/LocalDemoAuth.swift'), storeCopy, path.join(here, 'StoreConcurrency.swift'), '-o', executable]);
await run(executable, []);
console.log('Isolated fixture retained at ' + work);
