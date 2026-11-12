import test from 'node:test';
import assert from 'node:assert/strict';
import net from 'node:net';
import {WebSocketServer} from '../companion/node_modules/ws/wrapper.mjs';
import {createTunnelProxy} from '../companion/tunnel.mjs';
const token='dummy-test-token-'.repeat(3);
async function fixture(t, mode='echo'){
 const wss=new WebSocketServer({host:'127.0.0.1',port:0});await new Promise(r=>wss.once('listening',r));
 let destination,received='',auth;
 wss.on('connection',(ws,req)=>{auth=req.headers.authorization;ws.once('message',msg=>{
 destination=JSON.parse(msg.toString());ws.send('ready');
 ws.on('message',data=>{if(mode==='echo')ws.send(data,{binary:true});else{received+=data.toString();if(received.endsWith('hello')){ws.send(Buffer.from('HTTP/1.1 200 OK\r\nContent-Length: 2\r\nConnection: close\r\n\r\nok'));}}});
 });});
 const proxy=await createTunnelProxy({endpoint:`ws://127.0.0.1:${wss.address().port}/tunnel`,token,allowLocalTest:true});
 t.after(async()=>{await proxy.close();for(const ws of wss.clients)ws.terminate();await new Promise(r=>wss.close(r));});
 return {proxy,get destination(){return destination;},get auth(){return auth;},get received(){return received;}};
}
function request(port,raw,done){return new Promise((resolve,reject)=>{const s=net.connect(port,'127.0.0.1',()=>s.write(raw));let out=Buffer.alloc(0);s.on('data',d=>{out=Buffer.concat([out,d]);if(done(out)){s.destroy();resolve(out);}});s.on('error',reject);s.setTimeout(4000,()=>{s.destroy();reject(Error('timeout'));});});}
test('rejects insecure production endpoints and credentials',async()=>{
 for(const endpoint of ['ws://example.com/tunnel','wss://user:pass@example.com/tunnel','wss://example.com/tunnel?q=token','wss://example.com/other'])await assert.rejects(createTunnelProxy({endpoint,token}));
 await assert.rejects(createTunnelProxy({endpoint:'wss://example.com/tunnel',token:'short'}));
});
test('authenticated CONNECT preserves binary bytes including pre-read data',async t=>{
 const f=await fixture(t);const data=Buffer.alloc(50000,183);
 const raw=Buffer.concat([Buffer.from('CONNECT example.com:443 HTTP/1.1\r\nHost: example.com:443\r\n\r\n'),data]);
 const out=await request(f.proxy.port,raw,b=>b.length>=39+data.length);
 const split=out.indexOf('\r\n\r\n')+4;assert.deepEqual(out.subarray(split),data);assert.deepEqual(f.destination,{host:'example.com',port:443});assert.equal(f.auth,'Bearer '+token);
});
test('HTTP rewrites absolute URL, preserves body, strips proxy credentials',async t=>{
 const f=await fixture(t,'http');const out=await request(f.proxy.port,'POST http://example.com/find?q=1 HTTP/1.1\r\nHost: wrong.example\r\nProxy-Authorization: secret\r\nProxy-Connection: keep-alive\r\nContent-Length: 5\r\n\r\nhello',b=>b.toString().endsWith('\r\n\r\nok'));
 assert.match(out.toString(),/200 OK/);assert.match(f.received,/^POST \/find\?q=1 HTTP\/1.1\r\nHost: example.com\r\n/);assert.doesNotMatch(f.received,/secret|wrong.example|proxy-connection/i);assert.match(f.received,/Connection: close\r\n\r\nhello$/);assert.deepEqual(f.destination,{host:'example.com',port:80});
});
test('health is local, readonly and host-checked; invalid destinations rejected',async t=>{
 const f=await fixture(t);
 const health=await fetch(`http://127.0.0.1:${f.proxy.port}/.well-known/eloter-health`);assert.equal((await health.json()).service,'eloter-companion');assert.equal(f.destination,undefined);
 for(const raw of ['GET /.well-known/eloter-health HTTP/1.1\r\nHost: attacker.example\r\n\r\n','CONNECT example.com:22 HTTP/1.1\r\n\r\n','GET https://example.com/ HTTP/1.1\r\n\r\n','POST http://example.com/ HTTP/1.1\r\nContent-Length: 1\r\nTransfer-Encoding: chunked\r\n\r\n']){
 const result=await request(f.proxy.port,raw,b=>b.includes('\r\n\r\n'));assert.match(result.toString(),/400 Bad Request/);
 }
});
