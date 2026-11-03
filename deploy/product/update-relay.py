#!/usr/bin/env python3
"""Operator-only Relay update. Run beside compose.yml, never inside the Relay container."""
import argparse
import json
import os
from pathlib import Path
import re
import shutil
import subprocess
import time
from urllib.parse import urlparse
from urllib.request import urlopen


def run(*args, env=None, capture=False):
    return subprocess.run(args, env=env, check=True, text=True, capture_output=capture)


def read_json(url):
    with urlopen(url, timeout=30) as response:
        return json.load(response)


def newer(release, installed):
    current = tuple(int(n) for n in installed['version'].split('.'))
    latest = tuple(int(n) for n in release['version'].split('.'))
    return latest > current or (latest == current and release['build'] > int(installed['build']))


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    action = parser.add_mutually_exclusive_group(required=True)
    action.add_argument('--check', action='store_true')
    action.add_argument('--apply', action='store_true')
    parser.add_argument('--source', default='https://nekodot.com')
    parser.add_argument('--health', default='http://127.0.0.1:4349/health')
    parser.add_argument('--directory', type=Path, default=Path.cwd())
    args = parser.parse_args()
    source = args.source.rstrip('/')
    url = urlparse(source)
    if url.scheme != 'https' and not (url.scheme == 'http' and url.hostname in ('127.0.0.1', 'localhost')):
        parser.error('--source must use HTTPS (loopback permitted for local acceptance)')
    directory = args.directory.resolve()
    compose = ('docker', 'compose', '--project-directory', str(directory), '-f', str(directory / 'compose.yml'))
    release = read_json(source + '/downloads/latest.json')
    artifact = release['artifacts']['relay']
    if (release['schema'] != 1 or not re.fullmatch(r'\d+\.\d+\.\d+', release['version'])
            or not isinstance(release['build'], int)
            or not re.fullmatch(r'nekodot-relay:[a-zA-Z0-9_.-]+', artifact['image'])
            or not re.fullmatch(r'releases/[0-9.]+-[0-9]+/nekodot-relay\.tar', artifact['path'])):
        raise ValueError('Invalid published Relay release')
    installed = read_json(args.health)
    print('Installed Relay:', installed['version'], 'build', installed['build'])
    print('Latest Relay:', release['version'], 'build', release['build'])
    if not str(installed['build']).isdigit():
        raise RuntimeError('Development Relay cannot be updated in place; install a versioned image first')
    if not newer(release, installed):
        print('Already up to date or running a newer candidate.')
        return
    if args.check:
        print('Update available. Run again with --apply to restart only this Relay.')
        return
    container = run(*compose, 'ps', '-q', 'relay', capture=True).stdout.strip()
    if not container:
        raise RuntimeError('The configured Relay service must be running before updating')
    previous = run('docker', 'inspect', '--format', '{{.Config.Image}}', container, capture=True).stdout.strip()
    folder = directory / 'updates' / (release['version'] + '-' + str(release['build']))
    folder.mkdir(parents=True, exist_ok=True)
    archive = folder / 'nekodot-relay.tar'
    print('Downloading Relay image; existing service remains online.')
    with urlopen(source + '/downloads/' + artifact['path'], timeout=60) as response, archive.open('wb') as output:
        if urlparse(response.url).netloc != url.netloc:
            raise ValueError('Release download must remain on the configured server')
        shutil.copyfileobj(response, output, length=1024 * 1024)
    if archive.stat().st_size != artifact['size']:
        raise RuntimeError('Incomplete image download; current Relay was not changed')
    run('docker', 'load', '-i', str(archive))
    env = dict(os.environ, NEKODOT_RELAY_IMAGE=artifact['image'])
    try:
        run(*compose, 'up', '-d', '--no-deps', '--pull', 'never', 'relay', env=env)
        deadline = time.monotonic() + 60
        last_error = 'New Relay did not become ready'
        while time.monotonic() < deadline:
            try:
                health = read_json(args.health)
                if health.get('status') == 'ok' and health.get('version') == release['version'] and str(health.get('build')) == str(release['build']):
                    break
                last_error = 'Health endpoint still reports another version'
            except (OSError, ValueError) as error:
                last_error = str(error)
            time.sleep(2)
        else:
            raise RuntimeError(last_error)
    except Exception:
        print('Update failed; restoring the previous Relay image. Data and other services are retained.')
        run(*compose, 'up', '-d', '--no-deps', '--pull', 'never', 'relay', env=dict(os.environ, NEKODOT_RELAY_IMAGE=previous))
        raise
    # Persist just the image selection. Never print or replace private settings.
    env_file = directory / '.env'
    content = env_file.read_text() if env_file.exists() else ''
    if env_file.exists():
        backup = folder / ('relay-env-before-' + str(time.time_ns()))
        shutil.copy2(env_file, backup)
        backup.chmod(0o600)
    lines = [line for line in content.splitlines() if not line.startswith('NEKODOT_RELAY_IMAGE=')]
    lines.append('NEKODOT_RELAY_IMAGE=' + artifact['image'])
    env_file.write_text('\n'.join(lines) + '\n')
    env_file.chmod(0o600)
    print('Relay updated:', release['version'], 'build', release['build'])
    print('Previous image, downloaded archive, database, private settings and Node were retained.')


if __name__ == '__main__':
    main()
