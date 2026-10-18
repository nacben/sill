#!/usr/bin/env python3
"""Hardware pointer regression for a touchrig RIG_POINTER=1 run on a private simulator.
No events reach the Mac. Run the fixture and this checker concurrently; see README.md.
"""
import argparse
import json
import os
import pathlib
import re
import subprocess
import time

parser = argparse.ArgumentParser()
parser.add_argument('run', help='touchrig run name')
parser.add_argument('--simulator', required=True, help='UDID of this test’s private simulator')
args = parser.parse_args()
root = pathlib.Path(__file__).resolve().parents[2]
log = root / '.build' / 'touchrig' / (args.run + '.log')
env = dict(os.environ, DEVELOPER_DIR=os.environ.get('DEVELOPER_DIR', '/Applications/Xcode.app/Contents/Developer'))
for _ in range(240):
    contents = log.read_text(errors='replace') if log.exists() else ''
    points = re.findall(r'RIG POINTER READY (overlay|trackpad) (\d+),(\d+)', contents)
    if len(points) == 2:
        break
    time.sleep(.5)
else:
    raise SystemExit('FAIL: private pointer fixture did not become ready')
info = json.loads(subprocess.check_output(['xcrun', 'simctl', 'list', 'devices', '-j'], env=env, timeout=20))
simulator = next((d for devices in info['devices'].values() for d in devices if d['udid'] == args.simulator), None)
if not simulator or not simulator['name'].startswith('Sill right-click') or simulator['state'] != 'Booted':
    raise SystemExit('Refused: use a booted, private Sill right-click simulator created for this test')
steps = []
for area, x, y in points:
    steps += ['move -10000,-10000', f'move {x},{y}', 'wait 0.3',
              'buttons 1', 'wait 0.1', 'buttons 0', 'wait 0.5',
              'buttons 2', 'wait 0.1', 'buttons 0', 'wait 0.5',
              'buttons 2', 'wait 0.7', 'buttons 0', 'wait 0.5']
subprocess.run(['Tests/keyrig/run.sh', args.simulator, 'point', '|'.join(steps), '1', '1'],
               cwd=root, env=env, check=True, timeout=60)
time.sleep(.5)
contents = log.read_text(errors='replace')
failed = False
for area in ['overlay', 'trackpad']:
    actions = re.findall(r'POINTER ' + area + r' pointer\.(leftDown|leftUp|rightDown|rightUp)\(', contents)
    expected = ['leftDown', 'leftUp', 'rightDown', 'rightUp', 'rightDown', 'rightUp']
    ok = actions == expected
    print(('PASS' if ok else 'FAIL') + f': {area}: {actions}')
    failed |= not ok
raise SystemExit(1 if failed else 0)
