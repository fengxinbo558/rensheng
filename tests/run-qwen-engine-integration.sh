#!/bin/zsh
set -euo pipefail

TESTS_DIR="${0:A:h}"
PROJECT_DIR="${TESTS_DIR:h}"
SDK_PATH="$(xcrun --sdk macosx --show-sdk-path)"
TEST_ROOT="$(mktemp -d "/tmp/local-audio-qwen-engine.XXXXXX")"

: "${LOCAL_AUDIO_QWEN_INTEGRATION_REFERENCE:?请指定本地参考录音}"
: "${LOCAL_AUDIO_QWEN_INTEGRATION_REFERENCE_TEXT:?请指定参考录音对应文字}"
: "${LOCAL_AUDIO_QWEN_INTEGRATION_OUTPUT:=${TEST_ROOT}/natural-engine-result.wav}"
export LOCAL_AUDIO_QWEN_INTEGRATION_OUTPUT

swiftc \
  -sdk "${SDK_PATH}" \
  -target arm64-apple-macos14.0 \
  -parse-as-library \
  "${PROJECT_DIR}/AppConfiguration.swift" \
  "${PROJECT_DIR}/AudioProcessing.swift" \
  "${PROJECT_DIR}/VoiceLibrary.swift" \
  "${PROJECT_DIR}/RuntimeLocator.swift" \
  "${PROJECT_DIR}/NarrationSegment.swift" \
  "${PROJECT_DIR}/SpeechEngine.swift" \
  "${PROJECT_DIR}/QwenSpeechEngine.swift" \
  "${TESTS_DIR}/QwenSpeechEngineIntegration.swift" \
  -o "${TEST_ROOT}/QwenSpeechEngineIntegration"

"${TEST_ROOT}/QwenSpeechEngineIntegration"
