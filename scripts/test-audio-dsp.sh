#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
DSP_TEMP=$(mktemp -d)
trap 'rm -rf "$DSP_TEMP"' EXIT
SANITIZERS=undefined
if [ "$(uname -s)" = Darwin ]; then SANITIZERS=address,undefined; fi
cc -std=c11 -O2 -Wall -Wextra -Werror -fsanitize="$SANITIZERS" Tests/RenderAudioDSPTests/DSPTests.c Sources/RenderAudioDSP/AudioEffects.c -I Sources/RenderAudioDSP/include -lm -o "$DSP_TEMP/dsp-tests"
"$DSP_TEMP/dsp-tests"
