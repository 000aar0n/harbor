import {test} from 'node:test';
import assert from 'node:assert/strict';
import net from 'node:net';
import {once} from 'node:events';
import {WebSocketServer} from '../gecko/node_modules/ws/wrapper.mjs';
import {createTunnelProxy, proxyPreferences} from '../gecko/backend.mjs';

test('production tunnel requires encrypted authenticated configuration', async () => {
  await assert.rejects(createTunnelProxy({endpoint:'ws://example.com/tunnel', token:'x'.repeat(40)}));
  await assert.rejects(createTunnelProxy({endpoint:'wss://example.com/tunnel', token:'short'}));
  assert.equal(proxyPreferences(1234)['network.proxy.failover_direct'], false);
});
test('CONNECT streams binary traffic, carries auth, and stops without fallback', async () => {
  const token='test-only-token-not-a-real-secret-123456789';
  const wss=new WebSocketServer({host:'127.0.0.1',port:0});
  await once(wss,'listening');
  let target;
  wss.on('connection',(ws,req)=>{
    assert.equal(req.headers.authorization,'Bearer '+token);
    ws.once('message',data=>{target=JSON.parse(data);ws.send('ready');ws.on('message',(bytes,binary)=>{assert.ok(binary);ws.send(bytes);});});
  });
  const proxy=await createTunnelProxy({endpoint:`ws://127.0.0.1:${wss.address().port}/tunnel`,token,allowLocalTest:true});
  const socket=net.connect(proxy.port,'127.0.0.1');
  try {
    await once(socket,'connect');
    socket.write('CONNECT example.com:443 HTTP/1.1\r\nHost: example.com\r\n\r\n');
    const [header]=await once(socket,'data');
    assert.match(header.toString(),/^HTTP\/1.1 200/);
    assert.deepEqual(target,{host:'example.com',port:443});
    const payload=Buffer.alloc(50000,29);
    socket.write(payload);
    let result=Buffer.alloc(0);
    for await(const data of socket){result=Buffer.concat([result,data]);if(result.length>=payload.length)break;}
    assert.deepEqual(result,payload);
  } finally {
    socket.destroy();
    await proxy.close();
    for(const ws of wss.clients)ws.terminate();
    await new Promise(resolve=>wss.close(resolve));
  }
});
