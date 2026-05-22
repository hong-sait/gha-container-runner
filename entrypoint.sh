#!/usr/bin/env bash
set -euo pipefail

if [ "$(id -u)" = "0" ]; then
  if [ -S /var/run/docker.sock ]; then
    DOCKER_SOCK_GID="$(stat -c '%g' /var/run/docker.sock)"
    DOCKER_SOCK_GROUP="$(getent group "$DOCKER_SOCK_GID" | cut -d: -f1 || true)"

    if [ -z "$DOCKER_SOCK_GROUP" ]; then
      DOCKER_SOCK_GROUP="docker-host"
      groupadd --gid "$DOCKER_SOCK_GID" "$DOCKER_SOCK_GROUP"
    fi

    usermod --append --groups "$DOCKER_SOCK_GROUP" runner
  fi

  mkdir -p "${RUNNER_STATE_DIR:-/runner-state}" /home/runner/_work
  chown -R runner:runner "${RUNNER_STATE_DIR:-/runner-state}" /home/runner/_work

  export HOME=/home/runner
  export USER=runner
  export LOGNAME=runner
  exec runuser --preserve-environment --user runner -- /usr/local/bin/runner-entrypoint.sh "$@"
fi

if [ "$#" -gt 0 ]; then
  exec "$@"
fi

cd /home/runner

STATE_DIR="${RUNNER_STATE_DIR:-/runner-state}"
mkdir -p "$STATE_DIR"

restore_state() {
  for file in .runner .credentials .credentials_rsaparams; do
    if [ -f "$STATE_DIR/$file" ] && [ ! -f "/home/runner/$file" ]; then
      cp "$STATE_DIR/$file" "/home/runner/$file"
    fi
  done
}

save_state() {
  for file in .runner .credentials .credentials_rsaparams; do
    if [ -f "/home/runner/$file" ]; then
      cp "/home/runner/$file" "$STATE_DIR/$file"
    fi
  done
}

restore_state

if [ ! -f .runner ]; then
  : "${GITHUB_URL:?Set GITHUB_URL to the repository or organization URL, for example https://github.com/OWNER/REPO}"
  : "${RUNNER_TOKEN:?Set RUNNER_TOKEN to a fresh self-hosted runner registration token}"

  ./config.sh \
    --unattended \
    --url "$GITHUB_URL" \
    --token "$RUNNER_TOKEN" \
    --name "${RUNNER_NAME:-$(hostname)}" \
    --work "${RUNNER_WORKDIR:-_work}" \
    --labels "${RUNNER_LABELS:-docker,self-hosted}" \
    ${RUNNER_REPLACE_EXISTING:+--replace}

  save_state
fi

exec /home/runner/run.sh
