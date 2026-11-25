#!/usr/bin/env python3
"""Extract only exception metadata and crashed-thread symbols from synthetic simulator runs."""
import glob
import json
import os
import sys
import time

root, output, not_before = sys.argv[1], sys.argv[2], float(sys.argv[3])
paths = sorted(glob.glob(os.path.join(root, '**', '*Musicsk*.ips'), recursive=True),
               key=os.path.getmtime, reverse=True)
report = None
for path in paths:
    if os.path.getmtime(path) < not_before - 30:
        continue
    try:
        with open(path, encoding='utf-8') as file:
            content = file.read()
        # Apple IPS files contain a one-line header followed by a JSON payload.
        payload = json.loads(content.split('\n', 1)[1])
        if str(payload.get('procName', '')).lower() != 'musicsk':
            continue
        report = payload
        break
    except (OSError, ValueError, IndexError):
        continue
with open(output, 'w', encoding='utf-8') as file:
    if report is None:
        file.write('No simulator crash report found for this run.\n')
        sys.exit(0)
    exception = report.get('exception') or {}
    termination = report.get('termination') or {}
    file.write('Synthetic simulator crash metadata\n')
    for label, value in [('exception_type', exception.get('type')),
                         ('exception_signal', exception.get('signal')),
                         ('termination_namespace', termination.get('namespace')),
                         ('termination_code', termination.get('code')),
                         ('faulting_thread', report.get('faultingThread'))]:
        file.write(f'{label}: {value}\n')
    threads = report.get('threads') or []
    index = report.get('faultingThread')
    if isinstance(index, int) and 0 <= index < len(threads):
        for frame in threads[index].get('frames', [])[:40]:
            # Symbols and image indices only: no registers, URLs, cookies or user data.
            symbol = str(frame.get('symbol', '<unknown>')).replace('\n', ' ')[:256]
            file.write(f"frame: image={frame.get('imageIndex')} symbol={symbol}\n")
