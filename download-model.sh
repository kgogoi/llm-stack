#!/usr/bin/env bash
# ==============================================================================
# Automated Downloader for IBM Granite 125M Embedding Model Weights
# Model: ibm-granite/granite-embedding-125m-english (~240 MB)
# ==============================================================================

set -e

SOURCE="${BASH_SOURCE[0]}"
while [ -h "$SOURCE" ]; do
  DIR="$(cd -P "$(dirname "$SOURCE")" && pwd)"
  SOURCE="$(readlink "$SOURCE")"
  [[ $SOURCE != /* ]] && SOURCE="$DIR/$SOURCE"
done
SCRIPT_DIR="$(cd -P "$(dirname "$SOURCE")" && pwd)"

TARGET_DIR="${SCRIPT_DIR}/granite-model"
mkdir -p "$TARGET_DIR"

if [ -f "${TARGET_DIR}/model.safetensors" ] && [ -s "${TARGET_DIR}/model.safetensors" ]; then
    echo "✓ IBM Granite embedding model is already downloaded in: $TARGET_DIR"
    exit 0
fi

echo "=================================================================="
echo "  Downloading IBM Granite 125M English Embedding Weights (~240MB)"
echo "  Target: $TARGET_DIR"
echo "=================================================================="

# Method 1: Using Python huggingface_hub if available
if command -v python3 >/dev/null 2>&1 && python3 -c "import huggingface_hub" >/dev/null 2>&1; then
    echo "Using Python huggingface_hub..."
    python3 -c "
from huggingface_hub import snapshot_download
snapshot_download(
    repo_id='ibm-granite/granite-embedding-125m-english',
    local_dir='$TARGET_DIR',
    local_dir_use_symlinks=False
)
"
    echo "✓ Download complete via huggingface_hub."
    exit 0
fi

# Method 2: Using git clone with shallow depth if git-lfs is available
if command -v git >/dev/null 2>&1 && command -v git-lfs >/dev/null 2>&1; then
    echo "Using git clone with git-lfs..."
    TMP_DIR=$(mktemp -d)
    git clone --depth 1 https://huggingface.co/ibm-granite/granite-embedding-125m-english "$TMP_DIR"
    cp -r "$TMP_DIR"/* "$TARGET_DIR"/
    rm -rf "$TMP_DIR"
    echo "✓ Download complete via git-lfs."
    exit 0
fi

# Method 3: Direct curl download from Hugging Face CDN
echo "Using direct curl download from Hugging Face CDN..."
HF_BASE="https://huggingface.co/ibm-granite/granite-embedding-125m-english/resolve/main"

FILES=(
    "config.json"
    "model.safetensors"
    "modules.json"
    "special_tokens_map.json"
    "tokenizer.json"
    "tokenizer_config.json"
    "1_Pooling/config.json"
)

mkdir -p "${TARGET_DIR}/1_Pooling"

for file in "${FILES[@]}"; do
    echo "Fetching $file..."
    curl -L --fail --progress-bar "${HF_BASE}/${file}" -o "${TARGET_DIR}/${file}"
done

echo "=================================================================="
echo "✓ IBM Granite embedding model successfully downloaded!"
echo "=================================================================="
