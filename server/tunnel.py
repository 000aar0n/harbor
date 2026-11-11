"""Authenticated WebSocket byte tunnel. Never logs destinations or credentials."""
import asyncio
import hmac
import hashlib
import ipaddress
import os
import socket
from aiohttp import web, WSMsgType

TOKEN = os.environ.get('HARBOR_TOKEN', '')
MAX_CONNECTIONS = 128
active = set()

async def resolve_public(host, port):
    if not isinstance(host, str) or not host or len(host) > 253:
        raise ValueError('Invalid host')
    if type(port) is not int or port not in (80, 443):
        raise ValueError('Only web ports are supported')
    records = await asyncio.wait_for(asyncio.get_running_loop().getaddrinfo(
        host, port, type=socket.SOCK_STREAM), 10)
    addresses = {r[4][0] for r in records}
    if not addresses or any(not ipaddress.ip_address(a).is_global for a in addresses):
        raise ValueError('Destination is not public')
    return records[0][4][0]  # Connect to the checked address, avoiding DNS rebinding.

async def health(request):
    return web.json_response({'service': 'harbor-tunnel', 'region': 'US', 'ready': True})

async def setup(request):
    # Private download link. Do not log this URL or commit its value.
    expected = hmac.new(TOKEN.encode(), b'harbor-setup', hashlib.sha256).hexdigest()
    if not hmac.compare_digest(request.match_info['code'], expected):
        raise web.HTTPNotFound()
    hostname = os.environ.get('RENDER_EXTERNAL_HOSTNAME', 'harbor-tunnel-aaron.onrender.com')
    return web.json_response({'endpoint': 'wss://' + hostname + '/tunnel', 'token': TOKEN}, headers={
        'Content-Disposition': 'attachment; filename="Harbor-Connection.json"',
        'Cache-Control': 'no-store', 'Referrer-Policy': 'no-referrer',
        'X-Content-Type-Options': 'nosniff'})


def authorize(request):
    value = request.headers.get('Authorization', '')
    if not TOKEN or not hmac.compare_digest(value, 'Bearer ' + TOKEN):
        raise web.HTTPUnauthorized()

async def tunnel(request):
    authorize(request)
    if len(active) >= MAX_CONNECTIONS:
        raise web.HTTPServiceUnavailable()
    ws = web.WebSocketResponse(heartbeat=20, max_msg_size=131072)
    await ws.prepare(request)
    active.add(ws)
    writer = None
    pump = None
    try:
        opening = await asyncio.wait_for(ws.receive_json(), 15)
        address = await resolve_public(opening.get('host'), opening.get('port'))
        reader, writer = await asyncio.wait_for(asyncio.open_connection(address, opening['port']), 15)
        await ws.send_str('ready')
        async def download():
            while data := await reader.read(65536):
                await ws.send_bytes(data)
            await ws.close()
        pump = asyncio.create_task(download())
        async for message in ws:
            if message.type == WSMsgType.BINARY:
                writer.write(message.data)
                await writer.drain()
            else:
                break
    except (ValueError, OSError, asyncio.TimeoutError, TypeError, AttributeError):
        await ws.close(code=1008, message=b'Tunnel unavailable')
    finally:
        active.discard(ws)
        if writer:
            writer.close()
        if pump:
            pump.cancel()
        try:
            if pump:
                await asyncio.gather(pump, return_exceptions=True)
            if writer:
                await writer.wait_closed()
            await ws.close()
        except (OSError, asyncio.CancelledError):
            pass
    return ws

async def shutdown(app):
    await asyncio.gather(*(ws.close(code=1001, message=b'Server restart') for ws in list(active)))

def application():
    if len(TOKEN) < 32:
        raise RuntimeError('Set HARBOR_TOKEN to a random secret of at least 32 characters')
    app = web.Application(client_max_size=131072)
    app.router.add_get('/health', health)
    app.router.add_get('/setup/{code}', setup)
    app.router.add_get('/tunnel', tunnel)
    app.on_shutdown.append(shutdown)
    return app

if __name__ == '__main__':
    web.run_app(application(), host='0.0.0.0', port=int(os.environ.get('PORT', 10000)), access_log=None)
