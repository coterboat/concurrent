#!/bin/sh
# Wait for the playtest bots (the playtester's verdict and the play critic's review) on a push to
# main, pull them, and print what they found: tools/playtest/await_bots.py (--help for the options).
exec python3 "$(dirname "$0")/../tools/playtest/await_bots.py" "$@"
