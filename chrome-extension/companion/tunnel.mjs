import net from 'node:net';
import https from 'node:https';
import {WebSocket, createWebSocketStream} from 'ws';

export async function createTunnelProxy({endpoint, token, port = 0, allowLocalTest = false}) {
  const url = new URL(endpoint);
  const local = allowLocalTest && url.protocol === 'ws:' && url.hostname === '127.0.0.1';
  if ((!local && url.protocol !== 'wss:') || url.pathname !== '/tunnel' || url.username || url.password || url.search || url.hash || typeof token !== 'string' || token.length < 32 || /[\r\n]/.test(token)) throw Error('Invalid tunnel configuration');
  if (!Number.isInteger(port) || port < 0 || port > 65535) throw Error('Invalid listening port');
  // Honor the machine's configured upstream HTTP(S) proxy on supported Node releases.
  const agent = url.protocol === 'wss:' ? new https.Agent({proxyEnv:process.env}) : undefined;
  const clients = new Set();
  const server = net.createServer(socket => {
    clients.add(socket);
    let ws, buffer = Buffer.alloc(0);
    const deadline = setTimeout(() => socket.destroy(), 60000);
    socket.on('error', () => socket.destroy());
    socket.once('close', () => {clearTimeout(deadline); clients.delete(socket); ws?.terminate();});
    const fail = (code = '502 Bad Gateway') => {
      socket.end(`HTTP/1.1 ${code}\r\nConnection: close\r\nContent-Length: 0\r\n\r\n`);
    };
    const readHeader = data => {
      buffer = Buffer.concat([buffer, data]);
      const end = buffer.indexOf('\r\n\r\n');
      if ((end < 0 && buffer.length > 16384) || end > 16384) {fail('431 Request Header Fields Too Large'); socket.off('data', readHeader); return;}
      if (end < 0) return;
      socket.pause(); socket.off('data', readHeader);
      try {
        const [line, ...headers] = buffer.subarray(0, end).toString('latin1').split('\r\n');
        const match = /^([A-Z]+) (\S+) HTTP\/1\.[01]$/.exec(line);
        if (!match || headers.some(h => !/^[!#$%&'*+.^_`|~0-9A-Za-z-]+:[\t\x20-\x7e\x80-\xff]*$/.test(h))) throw Error('Malformed request');
        const [, method, resource] = match;
        const pairs = headers.map(h => [h.slice(0, h.indexOf(':')).toLowerCase(), h.slice(h.indexOf(':') + 1).trim()]);
        const hosts = pairs.filter(([k]) => k === 'host');
        if (resource === '/.well-known/eloter-health' && method === 'GET' && hosts.length === 1 && hosts[0][1] === `127.0.0.1:${server.address().port}`) {
          const body = JSON.stringify({service:'eloter-companion', version:'0.4.0'});
          socket.end(`HTTP/1.1 200 OK\r\nContent-Type: application/json\r\nCache-Control: no-store\r\nConnection: close\r\nContent-Length: ${Buffer.byteLength(body)}\r\n\r\n${body}`); return;
        }
        const connect = method === 'CONNECT';
        const target = new URL(connect ? 'https://' + resource : resource);
        const destinationPort = Number(target.port || (target.protocol === 'https:' ? 443 : 80));
        if (!target.hostname || target.username || target.password || target.hash || ![80,443].includes(destinationPort) || (connect ? target.protocol !== 'https:' || target.pathname !== '/' || target.search : target.protocol !== 'http:')) throw Error('Invalid destination');
        // Each HTTP request owns its upstream connection; no cross-host reuse or proxy credentials.
        let prefix;
        if (!connect) {
          const connectionTokens = pairs.filter(([k]) => k === 'connection').flatMap(([,v]) => v.toLowerCase().split(',').map(s=>s.trim()));
          const stripped = new Set(['host','proxy-authorization','proxy-connection','connection','keep-alive','upgrade', ...connectionTokens]);
          const lengths = pairs.filter(([k]) => k === 'content-length');
          const transfers = pairs.filter(([k]) => k === 'transfer-encoding');
          if (lengths.length > 1 || transfers.length > 1 || (lengths.length && transfers.length) || lengths.some(([,v])=>!/^\d+$/.test(v)) || transfers.some(([,v])=>v.toLowerCase() !== 'chunked')) throw Error('Ambiguous framing');
          prefix = Buffer.from(`${method} ${target.pathname}${target.search} HTTP/1.1\r\nHost: ${target.host}\r\n${pairs.filter(([k])=>!stripped.has(k)).map(([k,v])=>`${k}: ${v}\r\n`).join('')}Connection: close\r\n\r\n`, 'latin1');
        }
        ws = new WebSocket(url, {headers:{Authorization:'Bearer '+token}, handshakeTimeout:55000, perMessageDeflate:false, agent});
        ws.on('error', () => socket.destroy());
        ws.on('close', () => {if (!socket.destroyed) socket.end();});
        ws.on('open', () => ws.send(JSON.stringify({host:target.hostname.replace(/^\[|\]$/g,''), port:destinationPort})));
        ws.once('message', (message, binary) => {
          if (binary || message.toString() !== 'ready') {fail(); return;}
          clearTimeout(deadline);
          if (connect) socket.write('HTTP/1.1 200 Connection Established\r\n\r\n');
          const duplex = createWebSocketStream(ws);
          duplex.on('error', () => socket.destroy());
          if (prefix) duplex.write(prefix);
          const extra = buffer.subarray(end + 4);
          if (extra.length) socket.unshift(extra);
          socket.pipe(duplex).pipe(socket);
        });
      } catch {fail('400 Bad Request');}
    };
    socket.on('data', readHeader);
  });
  await new Promise((resolve,reject) => {server.once('error', reject); server.listen(port,'127.0.0.1',resolve);});
  return {port:server.address().port, close:async()=>{
    for (const client of clients) client.destroy();
    agent?.destroy();
    await new Promise(resolve=>server.close(resolve));
  }};
}
