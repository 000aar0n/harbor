export const PORT = 8877;
export function requireControl(settings) {
  if (settings.levelOfControl === 'not_controllable') throw Error('Chrome policy prevents this extension from changing the proxy. Ask your administrator to approve the project.');
  if (!['controllable_by_this_extension','controlled_by_this_extension'].includes(settings.levelOfControl)) throw Error('Another extension controls the proxy. This extension will not replace it.');
}
export function proxyValue() {
  return {mode:'fixed_servers', rules:{singleProxy:{scheme:'http',host:'127.0.0.1',port:PORT},bypassList:['localhost','127.0.0.1','[::1]']}};
}
export async function connect(api, fetcher = fetch) {
  requireControl(await api.proxy.settings.get({incognito:false}));
  const response = await fetcher(`http://127.0.0.1:${PORT}/.well-known/eloter-health`, {cache:'no-store',signal:AbortSignal.timeout(4000)});
  if (!response.ok || (await response.json()).service !== 'eloter-companion') throw Error('Start the eloter Node companion first.');
  requireControl(await api.proxy.settings.get({incognito:false}));
  await api.proxy.settings.set({value:proxyValue(),scope:'regular'});
}
export async function disconnect(api) {
  const settings = await api.proxy.settings.get({incognito:false});
  requireControl(settings);
  if (settings.levelOfControl === 'controlled_by_this_extension') await api.proxy.settings.clear({scope:'regular'});
}
export function active(settings) {
  return settings.levelOfControl === 'controlled_by_this_extension' && settings.value?.mode === 'fixed_servers' && settings.value?.rules?.singleProxy?.host === '127.0.0.1' && settings.value.rules.singleProxy.port === PORT;
}
