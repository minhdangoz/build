#!/usr/bin/env bash
set -euo pipefail

if [ $# -ne 1 ]; then
echo "Usage: $0 <image-file>"
exit 1
fi

IMAGE="$1"

burn-tool -v aml -r -e -b VIM1S -i "$IMAGE"
