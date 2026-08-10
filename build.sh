#!/bin/zsh
set -euo pipefail

SCRIPT_DIR="${0:A:h}"
WORKSPACE_ROOT="${SCRIPT_DIR:h:h:h}"
BUILD_FLAVOR="${BUILD_FLAVOR:-developer}"
OUTPUT_ROOT="${SCRIPT_DIR}/build"
APP_PATH="${OUTPUT_ROOT}/声音导演.app"
LEGACY_APP_PATH="${OUTPUT_ROOT}/LocalAudioProbe.app"
CONTENTS_PATH="${APP_PATH}/Contents"
MACOS_PATH="${CONTENTS_PATH}/MacOS"
RESOURCES_PATH="${CONTENTS_PATH}/Resources"
SDK_PATH="$(xcrun --sdk macosx --show-sdk-path)"

SHERPA_SOURCE="${WORKSPACE_ROOT}/spike/models/exploratory/sherpa-onnx-v1.13.1-osx-arm64-shared"
ZIPVOICE_SOURCE="${WORKSPACE_ROOT}/spike/models/exploratory/sherpa-onnx-zipvoice-distill-int8-zh-en-emilia"
VOCODER_SOURCE="${WORKSPACE_ROOT}/spike/models/exploratory/vocos_24khz.onnx"
DENOISER_SOURCE="${WORKSPACE_ROOT}/spike/models/exploratory/sherpa-onnx-speech-enhancement/gtcrn_simple.onnx"
REFERENCE_SOURCE="${WORKSPACE_ROOT}/spike/fixtures/voice-clone-v1/data/system-voice-smoke-reference.wav"
MP3_ENCODER_SOURCE="${SCRIPT_DIR}/Runtime/MP3Encoder"
THIRD_PARTY_SOURCE="${SCRIPT_DIR}/ThirdParty"

case "${BUILD_FLAVOR}" in
  developer|portable) ;;
  *)
    print -u2 -- "未知构建类型：${BUILD_FLAVOR}（可选 developer 或 portable）"
    exit 2
    ;;
esac

for required_path in \
  "${SHERPA_SOURCE}" \
  "${ZIPVOICE_SOURCE}" \
  "${VOCODER_SOURCE}" \
  "${DENOISER_SOURCE}" \
  "${REFERENCE_SOURCE}" \
  "${MP3_ENCODER_SOURCE}/lame" \
  "${MP3_ENCODER_SOURCE}/COPYING" \
  "${MP3_ENCODER_SOURCE}/lame-3.100.tar.gz" \
  "${THIRD_PARTY_SOURCE}/OpenNotebook/LICENSE" \
  "${THIRD_PARTY_SOURCE}/OpenNotebook/NOTICE.md"; do
  if [[ ! -e "${required_path}" ]]; then
    print -u2 -- "缺少应用资源：${required_path}"
    exit 1
  fi
done

if [[ "${APP_PATH}" != "${OUTPUT_ROOT}/声音导演.app" ]]; then
  print -u2 -- "拒绝清理意外的应用路径：${APP_PATH}"
  exit 2
fi
rm -rf "${APP_PATH}"
if [[ "${LEGACY_APP_PATH}" == "${OUTPUT_ROOT}/LocalAudioProbe.app" ]]; then
  rm -rf "${LEGACY_APP_PATH}"
fi
mkdir -p "${MACOS_PATH}" "${RESOURCES_PATH}/Models" "${RESOURCES_PATH}/Fixtures"
cp "${SCRIPT_DIR}/Info.plist" "${CONTENTS_PATH}/Info.plist"
/usr/bin/ditto "${SHERPA_SOURCE}" "${RESOURCES_PATH}/Sherpa"
/usr/bin/ditto "${ZIPVOICE_SOURCE}" "${RESOURCES_PATH}/Models/ZipVoice"
ZIPVOICE_TEST_AUDIO="${RESOURCES_PATH}/Models/ZipVoice/test_wavs"
if [[ "${ZIPVOICE_TEST_AUDIO}" == "${RESOURCES_PATH}/Models/ZipVoice/test_wavs" ]]; then
  rm -rf "${ZIPVOICE_TEST_AUDIO}"
fi
cp "${VOCODER_SOURCE}" "${RESOURCES_PATH}/Models/vocos_24khz.onnx"
cp "${DENOISER_SOURCE}" "${RESOURCES_PATH}/Models/gtcrn_simple.onnx"
cp "${REFERENCE_SOURCE}" "${RESOURCES_PATH}/Fixtures/default-reference.wav"
/usr/bin/ditto --norsrc "${MP3_ENCODER_SOURCE}" "${RESOURCES_PATH}/MP3Encoder"
/usr/bin/ditto --norsrc "${THIRD_PARTY_SOURCE}" "${RESOURCES_PATH}/ThirdParty"
chmod +x "${RESOURCES_PATH}/MP3Encoder/lame"

if [[ "${BUILD_FLAVOR}" == "portable" ]]; then
  plutil -insert LocalAudioPortableRuntime -bool true "${CONTENTS_PATH}/Info.plist"
  "${SCRIPT_DIR}/package-runtime.sh" "${RESOURCES_PATH}/QwenRuntime"
  /usr/bin/ditto --norsrc \
    "${WORKSPACE_ROOT}/spike/models/experimental/qwen3-tts-0.6b-base-8bit" \
    "${RESOURCES_PATH}/Models/Qwen3TTS"
  /usr/bin/ditto --norsrc \
    "${WORKSPACE_ROOT}/spike/models/experimental/deepfilternet-mlx/v3" \
    "${RESOURCES_PATH}/Models/DeepFilterNet/v3"
fi

SWIFT_SOURCES=("${SCRIPT_DIR}"/*.swift)
SWIFT_PATH_FLAGS=()
if [[ "${BUILD_FLAVOR}" == "portable" ]]; then
  SWIFT_PATH_FLAGS=(
    -D PORTABLE_RUNTIME
    -file-prefix-map "${WORKSPACE_ROOT}=."
    -debug-prefix-map "${WORKSPACE_ROOT}=."
  )
fi

swiftc \
  -sdk "${SDK_PATH}" \
  -target arm64-apple-macos14.0 \
  -parse-as-library \
  "${SWIFT_PATH_FLAGS[@]}" \
  "${SWIFT_SOURCES[@]}" \
  -o "${MACOS_PATH}/LocalAudioProbe"

plutil -lint "${CONTENTS_PATH}/Info.plist"
codesign --force --deep --sign - "${APP_PATH}"
codesign --verify --deep --strict "${APP_PATH}"

du -sh "${APP_PATH}"
print -r -- "${APP_PATH}"
