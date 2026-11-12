import {readFile} from 'node:fs/promises';
import {createTunnelProxy} from './tunnel.mjs';
const args = process.argv.slice(2);
try {
  if (args.length !== 2 || args[0] !== '--config') throw Error('Usage: node bridge.mjs --config /path/to/Harbor-Connection.json');
  const config = JSON.parse(await readFile(args[1], 'utf8'));
  const proxy = await createTunnelProxy({endpoint:config.endpoint, token:config.token, port:8877});
  console.log(`eloter companion ready on 127.0.0.1:${proxy.port}. Keep this Terminal window open. Connect using the Chrome extension.`);
  let stopping = false;
  const stop = async()=>{if(stopping)return; stopping=true; await proxy.close(); process.exit(0);};
  process.once('SIGINT',stop); process.once('SIGTERM',stop);
} catch (error) {
  console.error(error.code === 'EADDRINUSE' ? 'Port 8877 is busy. Close the other companion before restarting.' : error.code === 'ENOENT' ? 'Connection file not found. Check the path after --config.' : 'Companion could not start. Check the connection file and command format. Expected: node bridge.mjs --config /path/to/Harbor-Connection.json');
  process.exitCode = 1;
}
