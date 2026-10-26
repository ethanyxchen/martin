#!/usr/bin/env bash
set -euo pipefail

export PATH="/opt/homebrew/bin:$PATH"
cd "$(dirname "${BASH_SOURCE[0]}")/.."

[[ -e .env ]] || ln -s "$(dirname "$(git rev-parse --path-format=absolute --git-common-dir)")/.env" .env
(cd app && xcodegen generate)
