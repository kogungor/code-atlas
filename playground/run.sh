#!/usr/bin/env bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

nvim --clean -u "$ROOT_DIR/playground/minimal_init.lua" "$ROOT_DIR/playground/samples/lua_sample.lua"
