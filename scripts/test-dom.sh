#!/bin/bash
# Behaviour tests for the injected rules, run against real DOM fixtures.
#
# These execute the actual script extracted from BlockingScript.swift inside
# jsdom — not a reimplementation, which would pass while the shipped code was
# broken. jsdom is a test-only dependency and is installed on first run.
set -euo pipefail
cd "$(dirname "$0")/.."

if [ ! -d node_modules/jsdom ]; then
  echo "installing jsdom (test-only dependency)…"
  npm install --silent --no-audit --no-fund
fi
node tests/dom/run.mjs
