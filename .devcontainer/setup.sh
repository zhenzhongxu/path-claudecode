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

# --- Streaming sink CLIs (for integration tests) ---

# redis-cli
sudo apt-get install -y -qq redis-tools >/dev/null

# Detect architecture
ARCH=$(dpkg --print-architecture)   # amd64 or arm64

# nats CLI
NATS_VERSION="0.1.5"
curl -sL "https://github.com/nats-io/natscli/releases/download/v${NATS_VERSION}/nats-${NATS_VERSION}-${ARCH}.deb" -o /tmp/nats.deb
sudo dpkg -i /tmp/nats.deb
rm -f /tmp/nats.deb

# rpk (Redpanda CLI)
RPK_VERSION="24.3.7"
RPK_ARCH=$( [ "$ARCH" = "arm64" ] && echo "arm64" || echo "amd64" )
curl -sL "https://github.com/redpanda-data/redpanda/releases/download/v${RPK_VERSION}/rpk-linux-${RPK_ARCH}.zip" -o /tmp/rpk.zip
sudo unzip -o /tmp/rpk.zip -d /usr/local/bin rpk
sudo chmod +x /usr/local/bin/rpk
rm -f /tmp/rpk.zip

echo "All dependencies installed."
echo "  bash $(bash --version | head -1 | grep -oP '\d+\.\d+\.\d+')"
echo "  jq $(jq --version)"
echo "  curl $(curl --version | head -1 | awk '{print $2}')"
echo "  uuidgen $(uuidgen --version 2>&1 | head -1 || echo 'available')"
echo "  bats $(bats --version)"
echo "  claude $(claude --version 2>&1 | head -1)"
echo "  redis-cli $(redis-cli --version 2>&1 | head -1)"
echo "  nats $(nats --version 2>&1 | head -1)"
echo "  rpk $(rpk version 2>&1 | head -1)"
