#!/bin/zsh
set -euo pipefail

SCRIPT_DIR="${0:A:h}"
PROJECT_ROOT="${SCRIPT_DIR:h:h}"
MODEL_ROOT="${PROJECT_ROOT}/.emotion-models"
COSY_ROOT="${MODEL_ROOT}/CosyVoice3-0.5B-MLX-8bit-full"
CAMPP_ROOT="${MODEL_ROOT}/CamPlusPlus-Speaker-CoreML"
COSY_REPO="aufklarer/CosyVoice3-0.5B-MLX-8bit-full"
COSY_REVISION="b52fc1c3bf5f3b947d40c250639e5ebe347ece11"
CAMPP_REPO="aufklarer/CamPlusPlus-Speaker-CoreML"
CAMPP_REVISION="c3cbd83f0c1028cf753b3e3e67639854218206a1"
HF_CLI="${PROJECT_ROOT:h:h}/qwen3-mlx-python-probe/.venv/bin/hf"
HF_HOME_DIR="${PROJECT_ROOT}/.emotion-runtime/huggingface"
HF_DOWNLOAD_NO_PROXY="${HF_DOWNLOAD_NO_PROXY:-*}"

run_hf_download() {
  env \
    HF_HOME="${HF_HOME_DIR}" \
    HF_HUB_DISABLE_XET=1 \
    NO_PROXY="${HF_DOWNLOAD_NO_PROXY}" \
    no_proxy="${HF_DOWNLOAD_NO_PROXY}" \
    "${HF_CLI}" download "$@"
}

download_file() {
  local repository="$1"
  local revision="$2"
  local remote_path="$3"
  local destination_root="$4"
  local destination="${destination_root}/${remote_path}"
  local partial="${destination}.part"

  if [[ -s "${destination}" ]]; then
    print -r -- "已存在：${remote_path}"
    return
  fi
  mkdir -p "${destination:h}"
  print -r -- "下载：${remote_path}"
  /usr/bin/curl --fail --location --retry 5 --retry-delay 2 \
    --noproxy "${HF_DOWNLOAD_NO_PROXY}" \
    --continue-at - --output "${partial}" \
    "https://huggingface.co/${repository}/resolve/${revision}/${remote_path}?download=true"
  /bin/mv "${partial}" "${destination}"
}

mkdir -p "${COSY_ROOT}" "${CAMPP_ROOT}"

if [[ -x "${HF_CLI}" ]]; then
  run_hf_download \
    "${COSY_REPO}" \
    config.json \
    flow.safetensors \
    flow_noise.bin \
    hifigan.safetensors \
    llm.safetensors \
    merges.txt \
    speech_tokenizer.safetensors \
    tokenizer_config.json \
    vocab.json \
    --revision "${COSY_REVISION}" \
    --local-dir "${COSY_ROOT}" \
    --max-workers 8

  run_hf_download \
    "${CAMPP_REPO}" \
    CamPlusPlus.mlmodelc/analytics/coremldata.bin \
    CamPlusPlus.mlmodelc/coremldata.bin \
    CamPlusPlus.mlmodelc/metadata.json \
    CamPlusPlus.mlmodelc/model.mil \
    CamPlusPlus.mlmodelc/weights/weight.bin \
    --revision "${CAMPP_REVISION}" \
    --local-dir "${CAMPP_ROOT}" \
    --max-workers 8
else
  for model_file in \
    config.json \
    flow.safetensors \
    flow_noise.bin \
    hifigan.safetensors \
    llm.safetensors \
    merges.txt \
    speech_tokenizer.safetensors \
    tokenizer_config.json \
    vocab.json; do
    download_file "${COSY_REPO}" "${COSY_REVISION}" "${model_file}" "${COSY_ROOT}"
  done

  for campp_file in \
    CamPlusPlus.mlmodelc/analytics/coremldata.bin \
    CamPlusPlus.mlmodelc/coremldata.bin \
    CamPlusPlus.mlmodelc/metadata.json \
    CamPlusPlus.mlmodelc/model.mil \
    CamPlusPlus.mlmodelc/weights/weight.bin; do
    download_file "${CAMPP_REPO}" "${CAMPP_REVISION}" "${campp_file}" "${CAMPP_ROOT}"
  done
fi

print -r -- "${COSY_ROOT}"
print -r -- "${CAMPP_ROOT}"
