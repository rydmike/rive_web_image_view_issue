#!/usr/bin/env python3
"""Builds and captures the four cases: Rive's published wasm and the fixed wasm, each with dart2js and dart2wasm.

    FLUTTER_BIN=<flutter> CHROME_PATH=<chrome> FIXED_WASM_HOST=<url> python3 tool/run-matrix.py

FIXED_WASM_HOST is the folder holding the fixed build's wasm/ and wasm_compatibility/, passed to the app as
RIVE_NATIVE_WASM_HOST. The published cases pass nothing, so rive_native loads its own pinned CDN build.
"""
import json
import os
from pathlib import Path
import shutil
import subprocess
import sys
import time
import urllib.request

ROOT = Path(__file__).resolve().parents[1]
REPRO = ROOT / 'repro'
WORK = ROOT / '.work'
EVIDENCE = ROOT / 'evidence'
FLUTTER = os.environ.get('FLUTTER_BIN')
FIXED_HOST = os.environ.get('FIXED_WASM_HOST')
if not FLUTTER or not os.environ.get('CHROME_PATH') or not FIXED_HOST:
    sys.exit('Set FLUTTER_BIN, CHROME_PATH and FIXED_WASM_HOST')
CASES = [(wasm, compiler) for wasm in ['published', 'fixed'] for compiler in ['js', 'wasm']]


def clean(text: str) -> str:
    # Build tools can print absolute paths; evidence uses portable placeholders.
    for path, placeholder in [(str(ROOT.parent), '<workspace>'), (str(Path.home()), '<user-home>')]:
        text = text.replace(path, placeholder)
    return text


def run(cmd, log=None, cwd=REPRO):
    result = subprocess.run([str(c) for c in cmd], cwd=cwd, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True)
    if log:
        (EVIDENCE / log).write_text(clean(result.stdout))
    if result.returncode:
        print(clean(result.stdout), flush=True)
        raise RuntimeError(f'Command failed: {cmd[0]}')
    return result.stdout


EVIDENCE.mkdir(exist_ok=True)
run([FLUTTER, '--version'], log='flutter-version.txt')
run([FLUTTER, 'pub', 'get'], log='pub-get.log')
summary = []
for index, (wasm, compiler) in enumerate(CASES):
    name = f'{wasm}-{compiler}'
    out = WORK / 'builds' / name
    cmd = [FLUTTER, 'build', 'web', '--release', f'--output={out}']
    cmd += ['--wasm'] if compiler == 'wasm' else ['--no-wasm-dry-run']
    if wasm == 'fixed':
        cmd += [f'--dart-define=RIVE_NATIVE_WASM_HOST={FIXED_HOST}']
    # A build into a folder that already holds one can leave its assets out, so each case starts empty.
    if out.exists():
        shutil.rmtree(out)
    print(f'Building {name}', flush=True)
    run(cmd, log=f'{name}.build.log')
    if not (out / 'assets' / 'assets' / 'image_view.riv').is_file():
        raise RuntimeError(f'{name}: the build holds no assets/image_view.riv')
    port = 8300 + index
    server = subprocess.Popen([sys.executable, ROOT / 'tool/serve.py', out, '--port', str(port)],
                              stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    try:
        url = f'http://127.0.0.1:{port}/'
        for _ in range(100):
            try:
                urllib.request.urlopen(url, timeout=1).close()
                break
            except OSError:
                time.sleep(0.1)
        print(f'Capturing {name}', flush=True)
        run(['node', ROOT / 'tool/capture.mjs', url, EVIDENCE / f'{name}.json'], log=f'{name}.console.log', cwd=ROOT)
    finally:
        server.terminate()
        server.wait(timeout=10)
    record = json.loads((EVIDENCE / f'{name}.json').read_text())
    hosts = sorted({r.rsplit('/wasm', 1)[0] + '/' for r in record['requests'] if r.endswith('rive_native.wasm')})
    summary.append({'case': name, 'compiler': 'dart2wasm' if compiler == 'wasm' else 'dart2js',
                    'rive_native_wasm': hosts, 'checker_pixels': record.get('checker'),
                    'right_square_drawn': record.get('rightSquareDrawn'), 'ore_replay_messages': record.get('oreSkips'),
                    'page_errors': len(record.get('pageErrors', [])), 'complete': record.get('complete', False)})
(EVIDENCE / 'matrix.json').write_text(json.dumps(summary, indent=2) + '\n')
for row in summary:
    print(f"{row['case']}: right square drawn={row['right_square_drawn']} checker={row['checker_pixels']} "
          f"ore messages={row['ore_replay_messages']} wasm={row['rive_native_wasm']}")
