#!/bin/zsh
# Regenerate the Xcode project. Reads DEVELOPMENT_TEAM from .env (gitignored)
# so personal signing config stays out of the repo:
#   echo "DEVELOPMENT_TEAM=YOURTEAMID" > .env
set -e
cd "$(dirname "$0")"
if [[ -f .env ]]; then
    while IFS= read -r line || [[ -n "$line" ]]; do
        line="${line#"${line%%[![:space:]]*}"}"
        line="${line%"${line##*[![:space:]]}"}"
        [[ -z "$line" || "$line" == \#* ]] && continue
        if [[ "$line" == export[[:space:]]* ]]; then
            line="${line#export}"
            line="${line#"${line%%[![:space:]]*}"}"
        fi
        [[ "$line" == *=* ]] || continue
        key="${line%%=*}"
        val="${line#*=}"
        key="${key%"${key##*[![:space:]]}"}"
        val="${val#"${val%%[![:space:]]*}"}"
        case "$key" in
            ''|*[!A-Za-z0-9_]*|[0-9]*) continue ;;
        esac
        if [[ "$val" == \"*\" && "$val" == *\" && ${#val} -ge 2 ]]; then
            val="${val#\"}"
            val="${val%\"}"
        elif [[ "$val" == \'*\' && "$val" == *\' && ${#val} -ge 2 ]]; then
            val="${val#\'}"
            val="${val%\'}"
        fi
        export "$key=$val"
    done < .env
fi
exec xcodegen generate
