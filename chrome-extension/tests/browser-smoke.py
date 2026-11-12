import os, pathlib, subprocess, tempfile
from playwright.sync_api import sync_playwright, Error
root=pathlib.Path(__file__).resolve().parents[1]
fixture=subprocess.Popen(['node',str(root/'tests/browser-fixture.mjs')],stdout=subprocess.PIPE,text=True)
try:
    assert fixture.stdout.readline().strip()=='ready'
    with tempfile.TemporaryDirectory(prefix='eloter-chrome-test-') as profile, sync_playwright() as p:
        context=p.chromium.launch_persistent_context(profile,executable_path=os.environ.get('CHROME_BIN'),headless=True,channel='chromium',ignore_default_args=['--disable-extensions'],args=['--no-sandbox','--disable-extensions-except='+str(root/'extension'),'--load-extension='+str(root/'extension')])
        try:
            worker=context.service_workers[0] if context.service_workers else context.wait_for_event('serviceworker',timeout=20000)
            extension_id=worker.url.split('/')[2]
            popup=context.new_page();popup.goto(f'chrome-extension://{extension_id}/popup.html')
            popup.get_by_role('heading',name='Disconnected',exact=True).wait_for()
            popup.get_by_role('button',name='Connect',exact=True).click()
            popup.get_by_role('heading',name='Tunnel enabled',exact=True).wait_for(timeout=15000)
            page=context.new_page();page.goto('http://fixture.example/check',timeout=15000)
            assert page.title()=='Tunnel fixture'
            assert page.locator('h1').inner_text()=='Passed through eloter'
            popup.screenshot(path=str(root/'popup-tested.png'))
            fixture.terminate();fixture.wait(timeout=10)
            try:
                page.goto('http://fixture.example/after-stop',timeout=10000)
                raise AssertionError('Unexpected navigation after proxy stopped')
            except Error as error:
                assert 'ERR_PROXY_CONNECTION_FAILED' in str(error), str(error)
            popup.get_by_role('button',name='Disconnect',exact=True).click()
            popup.get_by_role('heading',name='Disconnected',exact=True).wait_for()
            settings=worker.evaluate('chrome.proxy.settings.get({incognito:false})')
            assert settings['levelOfControl']!='controlled_by_this_extension', settings
            print('PASS: real Chromium extension, Connect, HTTP tunnel, fail-closed, Disconnect restoration')
        finally: context.close()
finally:
    if fixture.poll() is None: fixture.terminate();fixture.wait(timeout=10)
