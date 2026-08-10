#!/bin/zsh
set -euo pipefail

SCRIPT_DIR="${0:A:h}"
RUNTIME_SOURCE="${SCRIPT_DIR}/.emotion-runtime/swift-probe-build/release"
COSY_SOURCE="${SCRIPT_DIR}/.emotion-models/CosyVoice3-0.5B-MLX-8bit-full"
CAMPP_SOURCE="${SCRIPT_DIR}/.emotion-models/CamPlusPlus-Speaker-CoreML"
SPEECH_LICENSE="${SCRIPT_DIR}/.emotion-runtime/source/speech-swift/LICENSE"
MLX_LICENSE="${SCRIPT_DIR}/.emotion-runtime/mlx-metal-0.31.1/mlx_metal-0.31.1.dist-info/licenses/LICENSE"
DESTINATION="${1:-}"

if [[ -z "${DESTINATION}" ]]; then
  print -u2 -- "用法：package-emotion-runtime.sh <应用内 Resources 目录>"
  exit 2
fi
case "${DESTINATION}" in
  *.app/Contents/Resources) ;;
  *)
    print -u2 -- "为安全起见，情绪运行时只能写入应用包的 Resources 目录"
    exit 2
    ;;
esac

MODEL_FILES=(
  config.json
  flow.safetensors
  flow_noise.bin
  hifigan.safetensors
  llm.safetensors
  merges.txt
  speech_tokenizer.safetensors
  tokenizer_config.json
  vocab.json
)
for required_path in \
  "${RUNTIME_SOURCE}/emotion-cosy-probe" \
  "${RUNTIME_SOURCE}/mlx.metallib" \
  "${CAMPP_SOURCE}/CamPlusPlus.mlmodelc/model.mil" \
  "${SPEECH_LICENSE}" \
  "${MLX_LICENSE}"; do
  if [[ ! -e "${required_path}" ]]; then
    print -u2 -- "缺少便携情绪资源：${required_path}"
    exit 1
  fi
done
for model_file in "${MODEL_FILES[@]}"; do
  if [[ ! -s "${COSY_SOURCE}/${model_file}" ]]; then
    print -u2 -- "缺少便携情绪模型：${model_file}"
    exit 1
  fi
done

BIN_DESTINATION="${DESTINATION}/EmotionRuntime/bin"
MODEL_DESTINATION="${DESTINATION}/Models/CosyVoice3"
CAMPP_DESTINATION="${DESTINATION}/Models/CamPlusPlus"
LICENSE_DESTINATION="${DESTINATION}/EmotionRuntime/Licenses"
mkdir -p \
  "${BIN_DESTINATION}" \
  "${MODEL_DESTINATION}" \
  "${CAMPP_DESTINATION}" \
  "${LICENSE_DESTINATION}"

/bin/cp "${RUNTIME_SOURCE}/emotion-cosy-probe" "${BIN_DESTINATION}/emotion-cosy-probe"
/bin/cp "${RUNTIME_SOURCE}/mlx.metallib" "${BIN_DESTINATION}/mlx.metallib"
chmod +x "${BIN_DESTINATION}/emotion-cosy-probe"
for model_file in "${MODEL_FILES[@]}"; do
  /bin/cp "${COSY_SOURCE}/${model_file}" "${MODEL_DESTINATION}/${model_file}"
done
/usr/bin/ditto --norsrc "${CAMPP_SOURCE}" "${CAMPP_DESTINATION}"
/bin/cp "${SPEECH_LICENSE}" "${LICENSE_DESTINATION}/speech-swift-LICENSE"
/bin/cp "${MLX_LICENSE}" "${LICENSE_DESTINATION}/mlx-LICENSE"

print -r -- "${DESTINATION}/EmotionRuntime"
