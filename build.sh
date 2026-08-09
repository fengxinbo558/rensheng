#!/bin/zsh
set -euo pipefail

SCRIPT_DIR="${0:A:h}"
WORKSPACE_ROOT="${SCRIPT_DIR:h:h:h}"
OUTPUT_ROOT="${SCRIPT_DIR}/build"
APP_PATH="${OUTPUT_ROOT}/LocalAudioProbe.app"
CONTENTS_PATH="${APP_PATH}/Contents"
MACOS_PATH="${CONTENTS_PATH}/MacOS"
RESOURCES_PATH="${CONTENTS_PATH}/Resources"
SDK_PATH="$(xcrun --sdk macosx --show-sdk-path)"

SHERPA_SOURCE="${WORKSPACE_ROOT}/spike/models/exploratory/sherpa-onnx-v1.13.1-osx-arm64-shared"
ZIPVOICE_SOURCE="${WORKSPACE_ROOT}/spike/models/exploratory/sherpa-onnx-zipvoice-distill-int8-zh-en-emilia"
VOCODER_SOURCE="${WORKSPACE_ROOT}/spike/models/exploratory/vocos_24khz.onnx"
DENOISER_SOURCE="${WORKSPACE_ROOT}/spike/models/exploratory/sherpa-onnx-speech-enhancement/gtcrn_simple.onnx"
REFERENCE_SOURCE="${WORKSPACE_ROOT}/spike/fixtures/voice-clone-v1/data/system-voice-smoke-reference.wav"

for required_path in \
  "${SHERPA_SOURCE}" \
  "${ZIPVOICE_SOURCE}" \
  "${VOCODER_SOURCE}" \
  "${DENOISER_SOURCE}" \
  "${REFERENCE_SOURCE}"; do
  if [[ ! -e "${required_path}" ]]; then
    print -u2 -- "缺少应用资源：${required_path}"
    exit 1
  fi
done

mkdir -p "${MACOS_PATH}" "${RESOURCES_PATH}/Models" "${RESOURCES_PATH}/Fixtures"
cp "${SCRIPT_DIR}/Info.plist" "${CONTENTS_PATH}/Info.plist"
/usr/bin/ditto "${SHERPA_SOURCE}" "${RESOURCES_PATH}/Sherpa"
/usr/bin/ditto "${ZIPVOICE_SOURCE}" "${RESOURCES_PATH}/Models/ZipVoice"
cp "${VOCODER_SOURCE}" "${RESOURCES_PATH}/Models/vocos_24khz.onnx"
cp "${DENOISER_SOURCE}" "${RESOURCES_PATH}/Models/gtcrn_simple.onnx"
cp "${REFERENCE_SOURCE}" "${RESOURCES_PATH}/Fixtures/default-reference.wav"

SWIFT_SOURCES=("${SCRIPT_DIR}"/*.swift)

swiftc \
  -sdk "${SDK_PATH}" \
  -target arm64-apple-macos14.0 \
  -parse-as-library \
  "${SWIFT_SOURCES[@]}" \
  -o "${MACOS_PATH}/LocalAudioProbe"

plutil -lint "${CONTENTS_PATH}/Info.plist"
codesign --force --deep --sign - "${APP_PATH}"
codesign --verify --deep --strict "${APP_PATH}"

print -r -- "${APP_PATH}"
