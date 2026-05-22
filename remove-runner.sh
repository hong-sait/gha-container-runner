#!/usr/bin/env bash
set -euo pipefail

if [ "$(id -u)" = "0" ]; then
  export HOME=/home/runner
  export USER=runner
  export LOGNAME=runner
  exec runuser --preserve-environment --user runner -- /usr/local/bin/remove-runner.sh "$@"
fi

cd /home/runner

STATE_DIR="${RUNNER_STATE_DIR:-/runner-state}"
for file in .runner .credentials .credentials_rsaparams; do
  if [ -f "$STATE_DIR/$file" ] && [ ! -f "/home/runner/$file" ]; then
    cp "$STATE_DIR/$file" "/home/runner/$file"
  fi
done

: "${RUNNER_TOKEN:?Set RUNNER_TOKEN to a fresh self-hosted runner removal token}"

if [ -f .runner ]; then
  ./config.sh remove --unattended --token "$RUNNER_TOKEN"
fi

rm -f "$STATE_DIR/.runner" "$STATE_DIR/.credentials" "$STATE_DIR/.credentials_rsaparams"
