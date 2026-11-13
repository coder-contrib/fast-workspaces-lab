#!/usr/bin/env bash
set -euo pipefail

[ -e "$HOME/.bashrc" ] || cp -rT /etc/skel "$HOME"

# /tmp is in the Pod filesystem. The home PVC does not cover it.
if [ -x /tmp/claude/.local/bin/claude ]; then
  echo 'Claude Code is already installed in this Pod'
  exit 0
fi

mkdir -p /tmp/claude
curl -fsSL https://claude.ai/install.sh | HOME=/tmp/claude bash
test -x /tmp/claude/.local/bin/claude
echo 'Claude Code was installed in this Pod'
