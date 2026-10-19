#!/usr/bin/env bash
set -euo pipefail

export PATH="/opt/homebrew/bin:$HOME/.bun/bin:$PATH"
cd "$(dirname "${BASH_SOURCE[0]}")/.."

[[ -e .env ]] || ln -s "$(dirname "$(git rev-parse --path-format=absolute --git-common-dir)")/.env" .env
(cd analyzer && bun install --frozen-lockfile)
(cd app && xcodegen generate)
