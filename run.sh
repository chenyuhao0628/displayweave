#!/usr/bin/env bash
# One build/run entry point, shared with the Codex Run action.
set -euo pipefail
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
exec "$ROOT_DIR/script/build_and_run.sh" "$@"
