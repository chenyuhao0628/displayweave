#!/bin/zsh
# Regenerate the Xcode project. Reads DEVELOPMENT_TEAM from .env (gitignored)
# so personal signing config stays out of the repo:
#   echo "DEVELOPMENT_TEAM=YOURTEAMID" > .env
set -e
cd "$(dirname "$0")"
[[ -f .env ]] && export $(grep -v '^#' .env | xargs)
exec xcodegen generate
