import json,os,pathlib,subprocess,sys,time,ipaddress
from selenium import webdriver
from selenium.webdriver.common.by import By
from selenium.webdriver.firefox.options import Options
from selenium.webdriver.firefox.service import Service
from selenium.webdriver.support.ui import WebDriverWait
from selenium.common.exceptions import WebDriverException

app=pathlib.Path(sys.argv[1]).resolve()
resources=app/'Contents/Resources'
node=resources/'runtime/node/bin/node'
backend=resources/'gecko/backend.mjs'
metadata=json.loads((resources/'runtime/firefox.json').read_text())
firefox=pathlib.Path.home()/'Library/Application Support/eloter/GeckoRuntime'/('Firefox-'+metadata['version']+'.app')/'Contents/MacOS/firefox'
assert firefox.is_file(), 'Startup check must prepare the Gecko runtime first'
service_path=str(pathlib.Path('build/geckodriver').resolve())
proxy=None
driver=None

def options(port=None):
    opts=Options()
    opts.binary_location=str(firefox)
    opts.set_preference('browser.shell.checkDefaultBrowser',False)
    opts.set_preference('browser.privatebrowsing.autostart',True)
    if port:
        prefs=json.loads(subprocess.check_output([str(node),'--input-type=module','-e',
            "import {proxyPreferences} from "+json.dumps(backend.as_uri())+"; console.log(JSON.stringify(proxyPreferences("+str(port)+")));"],text=True))
        for key,value in prefs.items():opts.set_preference(key,value)
    return opts

def browser(port=None):
    d=webdriver.Firefox(service=Service(service_path),options=options(port))
    d.set_page_load_timeout(50)
    return d

try:
    driver=browser()
    assert driver.capabilities['browserName']=='firefox'
    driver.get('https://www.bing.com/search?q=wikipedia')
    WebDriverWait(driver,30).until(lambda d: 'wikipedia' in d.find_element(By.TAG_NAME,'body').text.lower())
    ua=driver.execute_script('return navigator.userAgent')
    assert 'Firefox/' in ua and 'Chrome/' not in ua,ua
    print('PASS: Actual Gecko/Firefox engine rendered search results; user agent:',ua)
    fixture=pathlib.Path('build/pointer-fixture.html').resolve()
    fixture.write_text("<html><body><button id='play' style='width:500px;height:300px'>Play</button><script>document.querySelector('button').onclick=()=>document.querySelector('button').requestPointerLock();</script></body></html>")
    driver.get(fixture.as_uri())
    for cycle in range(2):
        driver.find_element(By.ID,'play').click()
        WebDriverWait(driver,10).until(lambda d:d.execute_script('return document.pointerLockElement !== null'))
        driver.execute_script('document.exitPointerLock()')
        WebDriverWait(driver,10).until(lambda d:d.execute_script('return document.pointerLockElement === null'))
    print('PASS: Gecko acquired and released pointer lock twice after real user clicks')
    driver.quit();driver=None

    env=dict(os.environ,ELOTER_TEST_MODE='1')
    proxy=subprocess.Popen([str(node),str(backend),'--proxy-only','ws://127.0.0.1:18765/tunnel','test-only-token-not-a-real-secret-123456789'],stdout=subprocess.PIPE,stderr=subprocess.PIPE,text=True,env=env)
    port=json.loads(proxy.stdout.readline())['port']
    driver=browser(port)
    driver.get('https://api.ipify.org/')
    ip=driver.find_element(By.TAG_NAME,'body').text.strip()
    try: ipaddress.ip_address(ip)
    except ValueError: raise AssertionError('Tunnel IP-check did not return an IP address: '+ip[:500])
    print('PASS: Gecko HTTPS browsing crossed the Node.js WebSocket tunnel; IP:',ip)
    proxy.terminate();proxy.wait(timeout=10);proxy=None
    blocked=False
    try:
        driver.get('https://www.iana.org/help/example-domains?eloter-gecko-failover-test=1')
    except WebDriverException as error:
        blocked='proxy' in str(error).lower() or 'connection' in str(error).lower()
    if not blocked:
        blocked='proxy' in driver.find_element(By.TAG_NAME,'body').text.lower()
    assert blocked,'Browser did not block navigation when the tunnel stopped'
    print('PASS: Stopped Node proxy blocked browsing; no direct fallback')
finally:
    if driver:
        try:driver.quit()
        except Exception:pass
    if proxy:
        proxy.terminate()
        try:proxy.wait(timeout=10)
        except subprocess.TimeoutExpired:proxy.kill()
