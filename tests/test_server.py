import asyncio
import os
import sys
import unittest
from unittest.mock import patch
sys.path.insert(0, os.path.join(os.path.dirname(__file__), '..', 'server'))
os.environ['HARBOR_TOKEN'] = 'test-only-token-not-a-real-secret-123456789'
import tunnel
from aiohttp import ClientSession, WSServerHandshakeError
from aiohttp.test_utils import TestServer

class TunnelTests(unittest.IsolatedAsyncioTestCase):
    async def asyncSetUp(self):
        self.server = TestServer(tunnel.application())
        await self.server.start_server()
        self.client = ClientSession()
    async def asyncTearDown(self):
        await self.client.close()
        await self.server.close()
    async def test_private_setup_download(self):
        import hmac, hashlib
        async with self.client.get(self.server.make_url('/setup/wrong')) as response:
            self.assertEqual(response.status,404)
        code = hmac.new(tunnel.TOKEN.encode(), b'harbor-setup', hashlib.sha256).hexdigest()
        async with self.client.get(self.server.make_url('/setup/'+code)) as response:
            self.assertEqual(response.status,200)
            self.assertEqual(response.headers['Cache-Control'],'no-store')
            self.assertEqual((await response.json())['token'],tunnel.TOKEN)
    async def test_unauthenticated_rejected(self):
        with self.assertRaises(WSServerHandshakeError) as result:
            await self.client.ws_connect(self.server.make_url('/tunnel'))
        self.assertEqual(result.exception.status, 401)
    async def test_private_and_non_web_destinations_rejected(self):
        for host, port in [('127.0.0.1',443), ('::1',443), ('169.254.169.254',80), ('example.com',22)]:
            with self.assertRaises(ValueError):
                await tunnel.resolve_public(host,port)
    async def test_binary_stream_and_cleanup(self):
        async def echo(reader, writer):
            try:
                while data := await reader.read(65536):
                    writer.write(data)
                    await writer.drain()
            finally:
                writer.close()
                await writer.wait_closed()
        tcp = await asyncio.start_server(echo, '127.0.0.1', 0)
        port = tcp.sockets[0].getsockname()[1]
        original = asyncio.open_connection
        async def local_connection(host, requested_port):
            return await original('127.0.0.1',port)
        try:
            with patch.object(tunnel, 'resolve_public', return_value='93.184.215.14'), patch.object(tunnel.asyncio, 'open_connection', side_effect=local_connection):
                ws = await self.client.ws_connect(self.server.make_url('/tunnel'), headers={'Authorization':'Bearer '+tunnel.TOKEN})
                await ws.send_json({'host':'example.com','port':443})
                self.assertEqual((await ws.receive()).data,'ready')
                payload = bytes(range(256))*400
                await ws.send_bytes(payload)
                received = b''
                while len(received) < len(payload):
                    received += (await asyncio.wait_for(ws.receive(),5)).data
                self.assertEqual(received,payload)
                await ws.close()
                for _ in range(100):
                    if not tunnel.active: break
                    await asyncio.sleep(0.01)
                self.assertFalse(tunnel.active)
        finally:
            tcp.close()
            await tcp.wait_closed()
    async def test_private_destination_closed_after_auth(self):
        ws = await self.client.ws_connect(self.server.make_url('/tunnel'), headers={'Authorization':'Bearer '+tunnel.TOKEN})
        await ws.send_json({'host':'127.0.0.1','port':443})
        await ws.receive()
        self.assertEqual(ws.close_code,1008)

if __name__ == '__main__': unittest.main()
