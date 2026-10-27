"""Read-only CDP integration probe against an isolated, locally launched Chromium."""
import argparse
import json
import os
from pathlib import Path
import subprocess
import tempfile
import time
import urllib.request

parser = argparse.ArgumentParser()
parser.add_argument('--chromium', required=True)
parser.add_argument('--root', required=True)
parser.add_argument('--runtime', required=True)
args = parser.parse_args()
home = Path(tempfile.mkdtemp(prefix='browser-spike-', dir=Path(args.runtime).parent))
os.environ['HERMES_HOME'] = str(home)
(home / 'config.yaml').write_text(json.dumps({'browser': {'cdp_url': 'http://127.0.0.1:19222'}}))
with (home / 'chromium.log').open('w') as log:
    browser = subprocess.Popen([
        args.chromium, '--headless=new', '--no-sandbox',
        '--remote-debugging-address=127.0.0.1', '--remote-debugging-port=19222',
        '--user-data-dir=' + str(home / 'chromium-profile'), '--no-first-run', 'about:blank',
    ], stdout=log, stderr=log)
    try:
        for attempt in range(50):
            if browser.poll() is not None:
                raise RuntimeError('Chromium exited; see retained runtime log: ' + str(home))
            try:
                with urllib.request.urlopen('http://127.0.0.1:19222/json/version', timeout=1):
                    break
            except OSError:
                time.sleep(0.1)
        from tools.browser_session_cdp import get_cdp_override_raw
        from tools.browser_cdp_tool import browser_cdp
        from tools.browser_use_cli import browser_exec_available
        version = json.loads(browser_cdp(method='Browser.getVersion'))
        targets = json.loads(browser_cdp(method='Target.getTargets'))
        result = {
            'configKey': 'browser.cdp_url',
            'resolvedConfig': get_cdp_override_raw(),
            'version': version,
            'browserExecAvailable': browser_exec_available(),
            'pageCount': len([item for item in targets['result']['targetInfos'] if item['type'] == 'page']),
            'passed': version.get('success') is True and targets.get('success') is True,
        }
        output = Path(args.root) / 'docs/fixtures/browser-cdp.json'
        output.write_text(json.dumps(result, indent=2) + '\n')
        print(json.dumps(result, indent=2))
        if not result['passed']:
            raise RuntimeError('Actual Hermes browser_cdp could not reach the isolated Chromium')
    finally:
        browser.terminate()
        browser.wait(timeout=15)
        print('Isolated browser profile retained at ' + str(home))
