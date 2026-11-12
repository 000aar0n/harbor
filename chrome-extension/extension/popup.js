const state=document.querySelector('#state'),detail=document.querySelector('#detail'),button=document.querySelector('#toggle'),message=document.querySelector('#message');
let connected=false;
function render(result){
  if(result.error){message.textContent=result.error;return;}
  connected=result.active;
  const blocked=!['controllable_by_this_extension','controlled_by_this_extension'].includes(result.level);
  state.textContent=blocked?'Unavailable':connected?'Tunnel enabled':'Disconnected';
  detail.textContent=blocked?'Chrome policy or another extension controls this setting.':connected?'Web requests use your companion. New connections use the Render exit.':'Start the Node companion, then connect.';
  document.querySelector('#light').classList.toggle('on',connected);
  button.textContent=connected?'Disconnect':'Connect';button.disabled=blocked;
}
button.addEventListener('click',async()=>{
  button.disabled=true;message.textContent='';
  try{render(await chrome.runtime.sendMessage({action:connected?'disconnect':'connect'}));}
  catch{message.textContent='Extension connection failed. Reopen this panel.';}
  finally{const r=await chrome.runtime.sendMessage({action:'status'}).catch(()=>null);if(r)render(r);}
});
document.querySelector('#check').addEventListener('click',()=>chrome.tabs.create({url:'https://api.ipify.org/'}));
render(await chrome.runtime.sendMessage({action:'status'}));
