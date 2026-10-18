#!/bin/bash
# Actual image conversion and clipboard generation 2 policy. Does not touch a system pasteboard.
here="$(cd "$(dirname "$0")" && pwd)"
source "$here/../common.sh"
swiftc -O -whole-module-optimization Sources/StreamProtocol/*.swift "$here/main.swift" -o "$out/check"
"$out/check"
