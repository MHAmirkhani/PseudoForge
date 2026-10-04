#!/usr/bin/env bash
# Minimal stand-in used by the pseudoforge test suite for engine *detection*.
# Real generation is covered by tests/test_engines.sh against the real builds.
echo "mock $(basename "$0") -- no calculation performed" >&2
exit 0
