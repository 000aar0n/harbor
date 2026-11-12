import test from 'node:test';
import assert from 'node:assert/strict';
import {connect,disconnect,proxyValue} from '../extension/controller.mjs';
function mock(level){const calls=[];return {calls,proxy:{settings:{get:async()=>({levelOfControl:level}),set:async value=>calls.push(['set',value]),clear:async value=>calls.push(['clear',value])}}};}
for(const level of ['not_controllable','controlled_by_other_extensions']) test('does not override '+level,async()=>{
 const api=mock(level);await assert.rejects(connect(api,()=>{throw Error('must not fetch');}));await assert.rejects(disconnect(api));assert.equal(api.calls.length,0);
});
test('connect checks companion and sets fixed loopback proxy without direct fallback',async()=>{
 const api=mock('controllable_by_this_extension');await connect(api,async()=>({ok:true,json:async()=>({service:'eloter-companion'})}));
 assert.deepEqual(api.calls,[['set',{value:proxyValue(),scope:'regular'}]]);assert.equal(proxyValue().mode,'fixed_servers');assert.equal(proxyValue().rules.singleProxy.host,'127.0.0.1');
});
test('offline or unrelated local service never changes proxy',async()=>{
 const api=mock('controllable_by_this_extension');await assert.rejects(connect(api,async()=>({ok:true,json:async()=>({service:'other'})})));assert.equal(api.calls.length,0);
});
test('rechecks policy immediately before mutation',async()=>{
 const api=mock('controllable_by_this_extension');let n=0;api.proxy.settings.get=async()=>({levelOfControl:++n===1?'controllable_by_this_extension':'not_controllable'});
 await assert.rejects(connect(api,async()=>({ok:true,json:async()=>({service:'eloter-companion'})})));assert.equal(api.calls.length,0);
});
test('disconnect clears only owned setting',async()=>{const api=mock('controlled_by_this_extension');await disconnect(api);assert.deepEqual(api.calls,[['clear',{scope:'regular'}]]);});
