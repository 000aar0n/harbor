import net from 'node:net';
import {spawn, execFile} from 'node:child_process';
import {promisify} from 'node:util';
import {mkdtemp, mkdir, writeFile, readFile, access, rename, rm} from 'node:fs/promises';
import {tmpdir} from 'node:os';
import path from 'node:path';
import {pathToFileURL} from 'node:url';
import readline from 'node:readline';
import {WebSocket, createWebSocketStream} from 'ws';

export function proxyPreferences(port) {
  if (!Number.isInteger(port) || port < 1 || port > 65535) throw Error('Invalid proxy port');
  return {
    'network.proxy.type': 1,
    'network.proxy.http': '127.0.0.1', 'network.proxy.http_port': port,
    'network.proxy.ssl': '127.0.0.1', 'network.proxy.ssl_port': port,
    'network.proxy.no_proxies_on': '', 'network.proxy.failover_direct': false,
    'network.proxy.allow_hijacking_localhost': true
  };
}

export async function createTunnelProxy({endpoint, token, allowLocalTest = false}) {
  const url = new URL(endpoint);
  const localTest = allowLocalTest && url.protocol === 'ws:' && url.hostname === '127.0.0.1';
  if ((!localTest && url.protocol !== 'wss:') || url.pathname !== '/tunnel' || url.username || url.password || url.search || url.hash || typeof token !== 'string' || token.length < 32) throw Error('Invalid tunnel configuration');
  const clients = new Set();
  const server = net.createServer(socket => {
    clients.add(socket);
    let ws;
    let buffer = Buffer.alloc(0);
    let deadline = setTimeout(() => socket.destroy(), 90000);
    const close = () => { clearTimeout(deadline); clients.delete(socket); ws?.terminate(); };
    socket.on('close', close);
    socket.on('error', () => socket.destroy());
    const readHeader = data => {
      buffer = Buffer.concat([buffer, data]);
      const end = buffer.indexOf('\r\n\r\n');
      if (end < 0) { if (buffer.length > 16384) socket.destroy(); return; }
      socket.pause();
      socket.off('data', readHeader);
      const line = buffer.subarray(0, end).toString('utf8').split('\r\n')[0];
      const match = /^CONNECT ([^\s]+) HTTP\/1\.[01]$/.exec(line);
      let target;
      try {
        if (!match) throw Error('CONNECT required');
        target = new URL('https://' + match[1]);
        const port = Number(target.port || 443);
        if (![80, 443].includes(port) || target.username || target.password || target.pathname !== '/' || target.search || target.hash) throw Error('Invalid destination');
        ws = new WebSocket(url, {headers: {Authorization: 'Bearer ' + token}, handshakeTimeout: 90000});
        ws.on('error', () => socket.destroy());
        ws.on('close', () => { if (!socket.destroyed) socket.end(); });
        ws.on('open', () => ws.send(JSON.stringify({host: target.hostname.replace(/^\[|\]$/g, ''), port})));
        ws.once('message', (message, binary) => {
          if (binary || message.toString() !== 'ready') { socket.destroy(); return; }
          clearTimeout(deadline);
          socket.write('HTTP/1.1 200 Connection Established\r\n\r\n');
          const duplex = createWebSocketStream(ws);
          duplex.on('error', () => socket.destroy());
          const extra = buffer.subarray(end + 4);
          if (extra.length) socket.unshift(extra);
          socket.pipe(duplex).pipe(socket);
        });
      } catch {
        socket.end('HTTP/1.1 405 Method Not Allowed\r\nConnection: close\r\n\r\n');
      }
    };
    socket.on('data', readHeader);
  });
  await new Promise((resolve, reject) => { server.once('error', reject); server.listen(0, '127.0.0.1', resolve); });
  return {port: server.address().port, close: async () => {
    for (const socket of clients) socket.destroy();
    await new Promise(resolve => server.close(resolve));
  }};
}

export async function makeProfile(port) {
  const folder = await mkdtemp(path.join(tmpdir(), 'eloter-gecko-'));
  const preferences = {
    'browser.shell.checkDefaultBrowser': false,
    'browser.startup.page': 0,
    'browser.sessionstore.resume_from_crash': false,
    'browser.privatebrowsing.autostart': true,
    'dom.security.https_only_mode': true,
    'toolkit.legacyUserProfileCustomizations.stylesheets': true,
    'ui.systemUsesDarkTheme': 1,
    ...(port ? proxyPreferences(port) : {'network.proxy.type': 0})
  };
  await writeFile(path.join(folder, 'user.js'), Object.entries(preferences).map(([key, value]) => `user_pref(${JSON.stringify(key)}, ${JSON.stringify(value)});`).join('\n') + '\n', {mode: 0o600});
  await mkdir(path.join(folder, 'chrome'));
  await writeFile(path.join(folder, 'chrome', 'userChrome.css'), ':root{--toolbar-bgcolor:#090d0a!important;--toolbar-color:#b0e7b7!important;--lwt-accent-color:#080c09!important;--lwt-text-color:#a2e8ae!important}#TabsToolbar,#nav-bar{background:#090d0a!important}#urlbar-background{background:#111b14!important;border-color:#35523d!important}');
  return folder;
}

export async function prepareFirefox(args) {
  const value = flag => args[args.indexOf(flag) + 1];
  if (args.includes('--firefox')) return value('--firefox');
  const cache = value('--runtime-cache');
  const metadata = JSON.parse(await readFile(value('--runtime-metadata'), 'utf8'));
  const destination = path.join(cache, `Firefox-${metadata.version}.app`);
  const execute = promisify(execFile);
  const validate = app => execute('/usr/bin/codesign', ['--verify','--deep','--strict','-R',metadata.requirement,app]);
  await mkdir(cache,{recursive:true});
  let exists = false;
  try { await access(destination); exists = true; } catch {}
  if (!exists) {
    const stage = await mkdtemp(path.join(cache,'prepare-'));
    const mount = path.join(stage,'image');
    let mounted = false;
    try {
      await mkdir(mount);
      await execute('/usr/bin/hdiutil',['attach',value('--runtime-dmg'),'-nobrowse','-readonly','-quiet','-mountpoint',mount]);
      mounted = true;
      const copied = path.join(stage,'Firefox.app');
      await execute('/usr/bin/ditto',[path.join(mount,'Firefox.app'),copied]);
      await validate(copied);
      await rename(copied,destination);
    } finally {
      if (mounted) await execute('/usr/bin/hdiutil',['detach',mount,'-quiet']).catch(()=>{});
      await rm(stage,{recursive:true,force:true});
    }
  }
  await validate(destination);
  return path.join(destination,'Contents','MacOS','firefox');
}

async function worker() {
  const args = process.argv.slice(2);
  let firefox;
  const home = args[args.indexOf('--home') + 1];
  let browser = null, proxy = null, profile = null, busy = false, quitting = false;
  const emit = value => process.stdout.write(JSON.stringify(value) + '\n');
  async function stop() {
    const child = browser; browser = null;
    if (child?.pid && child.exitCode === null && child.signalCode === null) {
      await new Promise(resolve => {
        child.once('exit', resolve);
        child.kill('SIGTERM');
        const timer = setTimeout(() => child.kill('SIGKILL'), 5000);
        timer.unref();
        child.once('exit', () => clearTimeout(timer));
      });
    }
    if (proxy) { await proxy.close(); proxy = null; }
    if (profile) { await rm(profile, {recursive: true, force: true}); profile = null; }
  }
  const input = readline.createInterface({input: process.stdin, crlfDelay: Infinity});
  input.on('line', async line => {
    if (busy) { emit({type: 'error', message: 'Browser is changing connections; please wait.'}); return; }
    busy = true;
    try {
      if (line.length > 65536) throw Error('Invalid command');
      const command = JSON.parse(line);
      if (command.command === 'quit') { quitting = true; await stop(); process.exit(0); }
      if (command.command === 'stop') { await stop(); emit({type: 'stopped'}); }
      else if (command.command === 'launch') {
        await stop();
        if (command.tunnel) proxy = await createTunnelProxy({endpoint: command.endpoint, token: command.token});
        profile = await makeProfile(proxy?.port);
        const target = command.tunnel ? 'https://api.ipify.org/?format=json' : pathToFileURL(home).href;
        browser = spawn(firefox, ['-no-remote', '-profile', profile, '-new-window', target], {stdio: ['ignore', 'ignore', 'pipe']});
        browser.stderr.on('data', () => {}); // Never forward profile paths or browsing data.
        browser.once('error', error => { stop().then(() => emit({type: 'error', message: error.message})); });
        browser.once('spawn', () => emit({type: 'running', tunnel: Boolean(proxy), pid: browser?.pid}));
        browser.once('exit', (code,signal) => { if (!busy && !quitting) { stop().then(() => emit({type: 'stopped', message: signal ? 'Firefox was terminated ('+signal+').' : code ? 'Firefox exited with code '+code+'.' : 'Browser closed. Session data cleared.'})); } });
      } else if (!['stop','quit'].includes(command.command)) throw Error('Unknown command');
    } catch (error) { await stop(); emit({type: 'error', message: error.message}); }
    finally { busy = false; }
  });
  async function shutdown() { if (quitting) return; quitting = true; await stop(); process.exit(0); }
  input.once('close', shutdown);
  process.once('SIGTERM', shutdown);
  process.once('SIGINT', shutdown);
  try {
    emit({type:'preparing'});
    firefox = await prepareFirefox(args);
    emit({type: 'ready', engine: 'Gecko/Firefox', backend: 'Node.js'});
  } catch(error) {
    emit({type:'error',message:'Gecko runtime setup failed: '+error.message});
    await shutdown();
  }
}

if (process.argv[1] && pathToFileURL(path.resolve(process.argv[1])).href === import.meta.url) {
  if (process.argv[2] === '--proxy-only') {
    const proxy = await createTunnelProxy({endpoint: process.argv[3], token: process.argv[4], allowLocalTest: process.env.ELOTER_TEST_MODE === '1'});
    console.log(JSON.stringify({port: proxy.port}));
    process.once('SIGTERM', async () => { await proxy.close(); process.exit(0); });
  } else { await worker(); }
}
