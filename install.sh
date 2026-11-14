#!/bin/bash
# gaze: webcam eye tracking for Apple silicon Macs (see README.md).
#   ./install.sh              python environment, the Core ML models and the `gaze` command
#   ./install.sh --uninstall  remove the environment, the models and the command (calibration is kept)
set -euo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
STATE="$HOME/Library/Application Support/gaze"
PY="$STATE/venv/bin/python"
CMD="$HOME/.local/bin/gaze"

if [[ "${1:-}" == "--uninstall" ]]; then
  rm -rf "$STATE/venv" "$STATE/gaze.sock" "$STATE"/*.mlmodelc "$CMD"
  echo "gaze removed (calibration kept in $STATE)"
  exit 0
fi

[[ "$(uname -m)" == "arm64" ]] || { echo "gaze needs an Apple silicon Mac" >&2; exit 1; }
command -v uv >/dev/null || { echo "uv not found: brew install uv" >&2; exit 1; }
mkdir -p "$STATE" "$(dirname "$CMD")"
[[ -x "$PY" ]] || uv venv --quiet --python 3.11 "$STATE/venv"
uv pip install --quiet --python "$PY" -r "$HERE/requirements.txt"

# Model files that are not ours to vendor: MediaPipe's face landmarker and UniGaze's 3D face model.
fetch() { [[ -s "$STATE/$1" ]] || curl -fsSL -o "$STATE/$1" "$2"; }
fetch face_landmarker.task https://storage.googleapis.com/mediapipe-models/face_landmarker/face_landmarker/float16/1/face_landmarker.task
fetch face_model.txt https://raw.githubusercontent.com/ut-vision/UniGaze/main/unigaze/data/face_model.txt

# The gaze models, as Core ML for the Neural Engine. Converting needs torch 2.7 and numpy 1.x, which the
# runtime environment does not: a throwaway one does it, once.
if [[ ! -d "$STATE/h14.mlmodelc" || ! -d "$STATE/l16.mlmodelc" ]]; then
  echo "building the Core ML models: downloads the UniGaze weights (~3 GB) and takes a few minutes, once"
  uv run --quiet --no-project --python 3.11 --with torch==2.7.0 --with 'numpy<2' --with coremltools==9.0 --with unigaze \
    "$HERE/convert.py" 2>&1 | grep -E "^(h14|l16):" || { echo "the Core ML build failed: run convert.py by hand (its docstring has the command) to see why" >&2; exit 1; }
fi

printf '#!/bin/sh\nexec "%s" "%s" "$@"\n' "$PY" "$HERE/gaze.py" > "$CMD"
chmod +x "$CMD"
echo "installed: run  gaze  to calibrate"
case ":$PATH:" in *":$HOME/.local/bin:"*) ;; *) echo "note: $HOME/.local/bin is not on your PATH" ;; esac
