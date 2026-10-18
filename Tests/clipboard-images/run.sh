#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/../.."
swift build -c release --product SillHost -j 2
mkdir -p .build/clipboard-images-integration
swiftc -O Tests/clipboard-images/board.swift -o .build/clipboard-images-integration/board
python3 Tests/clipboard-images/check.py
