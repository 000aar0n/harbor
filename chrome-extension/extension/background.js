import {connect,disconnect,active} from './controller.mjs';
let busy = false;
async function status(){
  const settings = await chrome.proxy.settings.get({incognito:false});
  const on = active(settings);
  await chrome.action.setBadgeText({text:on?'ON':''});
  await chrome.action.setBadgeBackgroundColor({color:'#256d43'});
  return {active:on,level:settings.levelOfControl};
}
chrome.proxy.settings.onChange.addListener(()=>{status().catch(()=>{});});
chrome.runtime.onMessage.addListener((message,sender,reply)=>{
  if(sender.id !== chrome.runtime.id) return;
  (async()=>{
    try {
      if(message.action==='status') return reply(await status());
      if(!['connect','disconnect'].includes(message.action)) throw Error('Unknown command');
      if(busy) throw Error('Connection change in progress.');
      busy=true;
      try {
        if(message.action==='connect') await connect(chrome); else await disconnect(chrome);
        reply(await status());
      } finally {busy=false;}
    } catch(error){reply({error:error.message.includes('fetch') || error.name==='TimeoutError' ? 'Cannot reach the Node companion. Start it in Terminal first.' : error.message});}
  })();
  return true;
});
status().catch(()=>{});
