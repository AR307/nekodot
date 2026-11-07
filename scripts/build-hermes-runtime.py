"""Build Nekodot's backend-only Hermes payload using Hermes's PM and assembler.

Run on the target OS, with a checkout at deploy/hermes-runtime-recipe.json's commit.
The source and optional tool store are read-only inputs; --out must be new.
"""
from __future__ import annotations

import argparse
import json
import os
from pathlib import Path
import subprocess
import sys
import tarfile
import time

ROOT = Path(__file__).resolve().parents[1]


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--source', type=Path, required=True)
    parser.add_argument('--out', type=Path, required=True)
    parser.add_argument('--cache', type=Path, required=True)
    parser.add_argument('--tools', type=Path, help='Already prepared official PM tool store')
    args = parser.parse_args()
    source, out, cache = args.source.resolve(), args.out.resolve(), args.cache.resolve()
    recipe = json.loads((ROOT / 'deploy/hermes-runtime-recipe.json').read_text(encoding='utf-8'))
    commit = subprocess.check_output(['git', '-C', str(source), 'rev-parse', 'HEAD'], text=True).strip()
    if commit != recipe['commit']:
        raise ValueError('Build from the selected Hermes release checkout')
    if out.exists():
        raise FileExistsError('Use a new output directory; existing builds are retained')
    out.mkdir(parents=True)
    started = time.monotonic()
    os.environ.update(HERMES_HOME=str(out.parent / (out.name + '-build-home')),
                      HERMES_RUNTIME_DIR=str(out / 'tools'), UV_CACHE_DIR=str(cache),
                      PYTHONUTF8='1', UV_NO_CONFIG='1')
    sys.path.insert(0, str(source))
    from scripts.bundles.payload import INERT_SNAPSHOT_DIRS, snapshot, seal_pm_runtime
    from scripts.build.agent import assemble
    from scripts.build.inputs import AgentInputs, RESOURCE_ENV, dependency_site

    code, store, venv = out / 'hermes-agent', out / 'tools', out / 'venv'
    print(f'Snapshot {recipe["hermesVersion"]}: backend and native resources', flush=True)
    snapshot(source, commit, code, exclude=INERT_SNAPSHOT_DIRS)
    # Carry the already-approved product fixes, rebased onto this pinned release.
    # Never patch the user's running checkout or their account data.
    for patch in recipe['patches']:
        subprocess.run(['git', 'apply', '--unsafe-paths', f'--directory={code.as_posix()}',
                        str(ROOT / 'deploy/hermes-patches' / patch['file'])], check=True, cwd=out.parent)
    # Only the packaged PM receives these same-version artifact pins.
    lock_path = code / 'pm/lock.json'
    lock_data = json.loads(lock_path.read_text(encoding='utf-8'))
    for name, artifacts in recipe['toolArtifacts'].items():
        lock_data['packages'][name]['artifacts'].update(artifacts)
    lock_path.write_text(json.dumps(lock_data, indent=2) + '\n', encoding='utf-8')
    sys.path.insert(0, str(code))
    from pm import stage_manager_runtime
    from pm.features import write_features
    from pm.install import _install
    from pm.lock import Facts, Lockfile
    from pm.packages import Venv
    from pm.registry import get_package, walk
    from pm.store import Store, current_target
    # Import stamp helpers only after PM: they transitively import PM themselves.
    from scripts.write_install_stamp import build_stamp
    target = current_target()
    names = [name for name in recipe['tools'] if get_package(name).missing_reason(target) is None]
    print(f'Tools: {", ".join(names)}', flush=True)
    lock, destination = Lockfile(lock_path), Store(store)
    source_store = Store(args.tools.resolve()) if args.tools else None
    prepared = Facts(source_store.root / 'facts.json') if source_store else None
    with destination.install_lock():
        staged = Facts(store / 'facts.json', strict=True)
        for package in walk(names):
            identity = (target, tuple(a['sha256'] for a in lock.artifacts(package.name, target)))
            reuse = prepared is not None and prepared.installed(
                package.name, lock.version(package.name), source_store.root, identity)
            print(f'    {"copy" if reuse else "acquire"} {package.name}', flush=True)
            _install(package, lock, staged, destination, target, _lock_held=True,
                     copy_from=(prepared, source_store) if reuse else None)
    facts = Facts(store / 'facts.json')
    python_fact = facts.get('python')
    python = get_package('python').binary(store / python_fact['entry'], target)
    print('Preparing independent package manager', flush=True)
    stage_manager_runtime(python=python, destination=out / 'pm-runtime', project=code / 'pm', cache=cache)
    seal_pm_runtime(out, python)
    print(f'Preparing runtime Python extras: {recipe["extras"]}', flush=True)
    manager_site = dependency_site(out / 'pm-runtime', python_fact['version'], target)
    subprocess.run([str(python), '-I', '-S', '-c',
        'import json,os,sys; from pathlib import Path; '
        'sys.path[:0]=sys.argv[1:3]; from pm.operations import build_environment; '
        'build_environment(source=Path(sys.argv[3]),out=Path(sys.argv[4]),'
        'python=Path(sys.executable),cache=Path(sys.argv[5]),extras=json.loads(sys.argv[6]),'
        'sealed=True,explicit=True,env=dict(os.environ))',
        str(code), str(manager_site), str(code), str(venv), str(cache), json.dumps(recipe['extras'])], check=True)
    # Keep the declared baseline, not every extra whose imports happen to resolve.
    write_features(recipe['extras'], out)
    facts.record_state('venv', Venv(code).expected_stamp(recipe['extras'], plugin_dirs=[]), recipe['extras'])
    site = dependency_site(venv, python_fact['version'], target)
    stamp = code / 'install-stamp.json'
    stamp.write_text(json.dumps(build_stamp(
        update_mechanism='external', distribution='nekodot', source='nekodot',
        commit=commit, branch=recipe['hermesVersion'], dirty=bool(recipe['patches']),
        base_version=recipe['hermesVersion'].removeprefix('v'), distance=0,
        runtime_dir='..',
    ), indent=2) + '\n', encoding='utf-8')
    assemble(AgentInputs(
        project=code / 'pyproject.toml', code=code, repo='hermes-agent', placement='contained',
        target=target, python=python, site_packages=site, environment=venv, tools=store,
        pm_runtime=out / 'pm-runtime', ref=recipe['hermesVersion'], stamp=stamp,
        resources={name: code / name for name in RESOURCE_ENV}, features=out / 'enabled-features.json',
    ), out)
    archive = out.parent / f'nekodot-hermes-{recipe["version"]}-{target}.tar.gz'
    if archive.exists():
        raise FileExistsError(archive)
    # PM-generated build locks and tool download staging never enter the archive.
    # No live environment/cache cleanup is performed.
    logical_bytes = 0
    with tarfile.open(archive, 'w:gz', compresslevel=6) as tar:
        for entry in sorted(out.rglob('*')):
            parts = entry.relative_to(out).parts
            if any(part.startswith('fetch-') or part in {'.install.lock', '.build.lock'} for part in parts):
                continue
            if entry.suffix.lower() == '.pdb':
                continue
            info = tar.gettarinfo(str(entry), arcname=str(entry.relative_to(out)))
            logical_bytes += info.size
            if info.isfile():
                with entry.open('rb') as content:
                    tar.addfile(info, content)
            else:
                tar.addfile(info)
    manifest = {
        **recipe, 'target': target, 'tools': names, 'archive': archive.name,
        'bytes': archive.stat().st_size, 'unpackedBytes': logical_bytes,
        'launcher': 'bin/hermes.exe' if target.startswith('win32') else 'bin/hermes',
        'buildSeconds': round(time.monotonic() - started, 1),
    }
    metadata = archive.with_name(f'{target}.json')
    metadata.write_text(json.dumps(manifest, indent=2) + '\n', encoding='utf-8')
    print(json.dumps(manifest, indent=2), flush=True)


if __name__ == '__main__':
    main()
