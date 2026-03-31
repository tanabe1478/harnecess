#!/usr/bin/env bash
# plan_filename.sh — Generate a random adjective-gerund-noun.md filename
# for Claude Code native plan format.
#
# Usage: bash scripts/plan_filename.sh
# Output: /path/to/.claude/plans/snazzy-bubbling-crystal.md
#
# Respects CLAUDE_PLANS_DIR env var, defaults to ~/.claude/plans/

set -e

PLANS_DIR="${CLAUDE_PLANS_DIR:-${HOME}/.claude/plans}"
mkdir -p "$PLANS_DIR"

ADJECTIVES=(
  bubbly curious dreamy eager fluffy gentle happy jolly keen lively
  mellow nimble perky quirky rustic snazzy tender vivid warm zesty
  bold calm deft fond giddy hazy icy jazzy kind lucid
  mild neat opal plush quiet rosy soft tidy ultra vast
  wiry young zippy agile brave cozy dull epic fair grand
)

GERUNDS=(
  bouncing brewing bubbling coalescing composing computing crunching dancing drifting floating
  frolicking gliding hatching humming jumping leaping munching nesting painting puzzling
  racing rolling scribbling singing skating skipping sliding spinning swimming tumbling
  twisting wading whistling wiggling zooming baking carving digging fishing gardening
  hiking jogging knitting mapping picking quilting rowing sailing tapping weaving
)

NOUNS=(
  acorn beaver biscuit brook cosmos crystal falcon grove harbor island
  jasper kernel lantern meadow nectar orchid pebble quartz ripple shore
  timber umbrella violet walnut yarrow zenith alpine breeze canyon delta
  ember fern glacier hollow iris juniper kelp lotus maple nebula
  oasis plume rossum sphinx tulip vertex willow xerus yucca zephyr
)

MAX_ATTEMPTS=10

for _attempt in $(seq 1 $MAX_ATTEMPTS); do
  adj="${ADJECTIVES[$((RANDOM % ${#ADJECTIVES[@]}))]}"
  ger="${GERUNDS[$((RANDOM % ${#GERUNDS[@]}))]}"
  noun="${NOUNS[$((RANDOM % ${#NOUNS[@]}))]}"
  filename="${adj}-${ger}-${noun}.md"
  filepath="${PLANS_DIR}/${filename}"

  if [ ! -f "$filepath" ]; then
    echo "$filepath"
    exit 0
  fi
done

# Fallback: append timestamp
adj="${ADJECTIVES[$((RANDOM % ${#ADJECTIVES[@]}))]}"
ger="${GERUNDS[$((RANDOM % ${#GERUNDS[@]}))]}"
noun="${NOUNS[$((RANDOM % ${#NOUNS[@]}))]}"
ts=$(date +%s)
echo "${PLANS_DIR}/${adj}-${ger}-${noun}-${ts}.md"
