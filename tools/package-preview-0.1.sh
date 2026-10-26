#!/usr/bin/env bash
# Compatibility alias for existing local automation; stable releases only.
set -euo pipefail
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
exec "$ROOT_DIR/tools/package-release.sh" "$@"
