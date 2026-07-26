#!/bin/zsh
# Local test driver for this worktree. Not part of the app; not committed.
# usage: run-tests.sh <logpath> [only-testing-target] [parallel:YES|NO]
cd /Users/nikitabogdanov/PycharmProjects/cypress/.claude/worktrees/agent-a6e995350333565bc
LOG="${1:-/private/tmp/claude-501/-Users-nikitabogdanov-PycharmProjects-cypress/0d7c1eed-65e3-4ed3-b24f-b64dc9fb8b1c/scratchpad/test.log}"
ONLY="${2:-CypressTests}"
PAR="${3:-YES}"
rm -f "$LOG"
xcodebuild test -scheme Cypress \
  -destination 'platform=iOS Simulator,id=3A1F212D-8F3A-41F1-AF72-EC95E155A4C9' \
  -only-testing:"$ONLY" \
  -parallel-testing-enabled "$PAR" \
  -derivedDataPath .ddspecies > "$LOG" 2>&1
echo "EXIT=$?" >> "$LOG"
