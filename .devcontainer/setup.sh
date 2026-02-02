#!/bin/bash
set -euo pipefail

echo "Installing Path dependencies..."

sudo apt-get update -qq
sudo apt-get install -y -qq jq curl uuid-runtime coreutils >/dev/null

# Install bats-core for testing
BATS_VERSION="1.11.1"
sudo git clone --depth 1 --branch "v${BATS_VERSION}" https://github.com/bats-core/bats-core.git /tmp/bats-core
sudo /tmp/bats-core/install.sh /usr/local
sudo rm -rf /tmp/bats-core

# Install Claude Code
npm install -g @anthropic-ai/claude-code

echo "All dependencies installed."
echo "  bash $(bash --version | head -1 | grep -oP '\d+\.\d+\.\d+')"
echo "  jq $(jq --version)"
echo "  curl $(curl --version | head -1 | awk '{print $2}')"
echo "  uuidgen $(uuidgen --version 2>&1 | head -1 || echo 'available')"
echo "  bats $(bats --version)"
echo "  claude $(claude --version 2>&1 | head -1)"
