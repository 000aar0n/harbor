import {WebSocketServer} from '../companion/node_modules/ws/wrapper.mjs';
import {createTunnelProxy} from '../companion/tunnel.mjs';
const wss=new WebSocketServer({host:'127.0.0.1',port:0});
await new Promise(r=>wss.once('listening',r));
wss.on('connection',ws=>ws.once('message',data=>{
 const target=JSON.parse(data.toString());ws.send('ready');let request='';
 ws.on('message',data=>{request+=data.toString();if(!request.includes('\r\n\r\n'))return;
 if(target.host!=='fixture.example'){ws.close();return;}
 const body='<html><title>Tunnel fixture</title><h1>Passed through eloter</h1></html>';
 ws.send(Buffer.from(`HTTP/1.1 200 OK\r\nContent-Type: text/html\r\nCache-Control: no-store\r\nConnection: close\r\nContent-Length: ${Buffer.byteLength(body)}\r\n\r\n${body}`));
 });
}));
const proxy=await createTunnelProxy({endpoint:`ws://127.0.0.1:${wss.address().port}/tunnel`,token:'local-test-token-'.repeat(3),port:8877,allowLocalTest:true});
console.log('ready');
process.once('SIGTERM',async()=>{await proxy.close();for(const ws of wss.clients)ws.terminate();wss.close(()=>process.exit(0));});
