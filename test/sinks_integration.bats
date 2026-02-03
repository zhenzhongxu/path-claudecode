#!/usr/bin/env bats
# Integration tests for streaming sink delivery via the command sink type.
#
# These tests require running streaming services (Redis, NATS, Redpanda)
# as provided by the devcontainer docker-compose setup.
#
# Skipped unless PATH_SINK_TESTS=1 is set:
#   PATH_SINK_TESTS=1 bats test/sinks_integration.bats

load test_helper

setup() {
  if [ "${PATH_SINK_TESTS:-}" != "1" ]; then
    skip "streaming sink tests require PATH_SINK_TESTS=1 and running services"
  fi
  setup_sandbox
  run_install
}

teardown() { teardown_sandbox; }

# --- Redis Streams ---

@test "redis: command sink delivers event to Redis Stream" {
  local stream_key="path:events:${BATS_TEST_NAME}"

  # Configure command sink to push to Redis Stream
  jq --arg cmd "redis-cli -h redis -p 6379 -x XADD ${stream_key} '*' data" \
    '.sinks = [
      {"type":"jsonl","path":".claude/path-kernel/event-log.jsonl","enabled":true},
      {"type":"command","command":$cmd,"enabled":true}
    ]' .claude/path-kernel/config.json > /tmp/cfg.json && mv /tmp/cfg.json .claude/path-kernel/config.json

  # Fire event
  bash .claude/hooks/append-event.sh "test:redis" '{"sink":"redis"}' 0 2>/dev/null
  sleep 1

  # Verify event arrived in stream
  local result
  result=$(redis-cli -h redis --raw XREVRANGE "$stream_key" + - COUNT 1)
  [[ "$result" == *"test:redis"* ]]

  # Cleanup
  redis-cli -h redis DEL "$stream_key" >/dev/null
}

# --- NATS JetStream ---

@test "nats: command sink delivers event to JetStream" {
  local stream_name="PATH_EVENTS_$$"
  local subject="path.events.$$"

  # Create JetStream stream
  nats stream add "$stream_name" \
    --subjects "$subject" \
    --defaults \
    --server nats://nats:4222 2>/dev/null

  # Configure command sink to publish to NATS
  jq --arg cmd "nats pub ${subject} --server nats://nats:4222 --force-stdin" \
    '.sinks = [
      {"type":"jsonl","path":".claude/path-kernel/event-log.jsonl","enabled":true},
      {"type":"command","command":$cmd,"enabled":true}
    ]' .claude/path-kernel/config.json > /tmp/cfg.json && mv /tmp/cfg.json .claude/path-kernel/config.json

  # Fire event
  bash .claude/hooks/append-event.sh "test:nats" '{"sink":"nats"}' 0 2>/dev/null
  sleep 1

  # Verify event arrived in stream (decode base64 data field)
  local result
  result=$(nats stream get "$stream_name" -S "$subject" --server nats://nats:4222 -j 2>/dev/null | jq -r '.data | @base64d')
  [[ "$result" == *"test:nats"* ]]

  # Cleanup
  nats stream rm "$stream_name" -f --server nats://nats:4222 2>/dev/null
}

# --- Redpanda (Kafka API) ---

@test "redpanda: command sink delivers event to Kafka topic" {
  local topic="path-events-${BATS_TEST_NUMBER}"

  # Create topic
  rpk topic create "$topic" --brokers redpanda:9092 2>/dev/null

  # Configure command sink to produce to Redpanda
  jq --arg cmd "rpk topic produce ${topic} --brokers redpanda:9092" \
    '.sinks = [
      {"type":"jsonl","path":".claude/path-kernel/event-log.jsonl","enabled":true},
      {"type":"command","command":$cmd,"enabled":true}
    ]' .claude/path-kernel/config.json > /tmp/cfg.json && mv /tmp/cfg.json .claude/path-kernel/config.json

  # Fire event
  bash .claude/hooks/append-event.sh "test:redpanda" '{"sink":"redpanda"}' 0 2>/dev/null
  sleep 2

  # Verify event arrived in topic
  local result
  result=$(rpk topic consume "$topic" --num 1 --brokers redpanda:9092 --format '%v\n' 2>/dev/null)
  [[ "$result" == *"test:redpanda"* ]]

  # Cleanup
  rpk topic delete "$topic" --brokers redpanda:9092 2>/dev/null
}

# --- Fan-out: all three sinks simultaneously ---

@test "fan-out: event reaches all three streaming sinks simultaneously" {
  local redis_key="path:events:fanout"
  local nats_stream="PATH_EVENTS_FANOUT_$$"
  local nats_subject="path.events.fanout.$$"
  local rpk_topic="path-events-fanout-${BATS_TEST_NUMBER}"

  # Setup NATS stream and Redpanda topic
  nats stream add "$nats_stream" \
    --subjects "$nats_subject" \
    --defaults \
    --server nats://nats:4222 2>/dev/null
  rpk topic create "$rpk_topic" --brokers redpanda:9092 2>/dev/null

  # Configure all three command sinks + jsonl
  jq \
    --arg redis_cmd "redis-cli -h redis -p 6379 -x XADD ${redis_key} '*' data" \
    --arg nats_cmd "nats pub ${nats_subject} --server nats://nats:4222 --force-stdin" \
    --arg rpk_cmd "rpk topic produce ${rpk_topic} --brokers redpanda:9092" \
    '.sinks = [
      {"type":"jsonl","path":".claude/path-kernel/event-log.jsonl","enabled":true},
      {"type":"command","command":$redis_cmd,"enabled":true},
      {"type":"command","command":$nats_cmd,"enabled":true},
      {"type":"command","command":$rpk_cmd,"enabled":true}
    ]' .claude/path-kernel/config.json > /tmp/cfg.json && mv /tmp/cfg.json .claude/path-kernel/config.json

  # Fire single event
  bash .claude/hooks/append-event.sh "test:fanout" '{"sink":"all"}' 0 2>/dev/null
  sleep 2

  # Verify jsonl
  [ "$(wc -l < .claude/path-kernel/event-log.jsonl | tr -d ' ')" -ge 1 ]
  [[ "$(head -1 .claude/path-kernel/event-log.jsonl)" == *"test:fanout"* ]]

  # Verify Redis
  local redis_result
  redis_result=$(redis-cli -h redis --raw XREVRANGE "$redis_key" + - COUNT 1)
  [[ "$redis_result" == *"test:fanout"* ]]

  # Verify NATS (decode base64 data field)
  local nats_result
  nats_result=$(nats stream get "$nats_stream" -S "$nats_subject" --server nats://nats:4222 -j 2>/dev/null | jq -r '.data | @base64d')
  [[ "$nats_result" == *"test:fanout"* ]]

  # Verify Redpanda
  local rpk_result
  rpk_result=$(rpk topic consume "$rpk_topic" --num 1 --brokers redpanda:9092 --format '%v\n' 2>/dev/null)
  [[ "$rpk_result" == *"test:fanout"* ]]

  # Cleanup
  redis-cli -h redis DEL "$redis_key" >/dev/null
  nats stream rm "$nats_stream" -f --server nats://nats:4222 2>/dev/null
  rpk topic delete "$rpk_topic" --brokers redpanda:9092 2>/dev/null
}
