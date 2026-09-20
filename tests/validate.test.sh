#!/usr/bin/env bash
set -euo pipefail
omarchy plugin validate .
echo "Manifest is valid!"
bash "$(dirname "$0")/security.test.sh"
