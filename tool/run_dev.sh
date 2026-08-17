#!/bin/zsh

set -e

if [ ! -f "env/dev.json" ]; then
  echo "ERROR: env/dev.json not found."
  exit 1
fi

flutter run \
  --dart-define-from-file=env/dev.json \
  "$@"
