#!/bin/zsh
set -euo pipefail

TESTS_DIR="${0:A:h}"
PROJECT_DIR="${TESTS_DIR:h}"
SDK_PATH="$(xcrun --sdk macosx --show-sdk-path)"
TEST_ROOT="$(mktemp -d "/tmp/voice-director-spoken-ab.XXXXXX")"

: "${LOCAL_AUDIO_AB_APP_SUPPORT:?请指定应用本地资料目录}"
: "${LOCAL_AUDIO_AB_VOICE_ID:?请指定本地音色 ID}"
: "${LOCAL_AUDIO_AB_OUTPUT_DIR:?请指定试听输出目录}"

swiftc \
  -sdk "${SDK_PATH}" \
  -target arm64-apple-macos14.0 \
  -parse-as-library \
  "${PROJECT_DIR}/AppConfiguration.swift" \
  "${PROJECT_DIR}/AudioProcessing.swift" \
  "${PROJECT_DIR}/VoiceLibrary.swift" \
  "${PROJECT_DIR}/RuntimeLocator.swift" \
  "${PROJECT_DIR}/NarrationSegment.swift" \
  "${PROJECT_DIR}/NarrationProject.swift" \
  "${PROJECT_DIR}/SpokenScriptValidator.swift" \
  "${PROJECT_DIR}/SpokenScriptDirector.swift" \
  "${PROJECT_DIR}/NarrationRules.swift" \
  "${PROJECT_DIR}/NarrationDirector.swift" \
  "${PROJECT_DIR}/SpeechEngine.swift" \
  "${PROJECT_DIR}/QwenSpeechEngine.swift" \
  "${PROJECT_DIR}/ProjectStore.swift" \
  "${PROJECT_DIR}/GenerationJob.swift" \
  "${PROJECT_DIR}/GenerationJournal.swift" \
  "${PROJECT_DIR}/GenerationQueue.swift" \
  "${PROJECT_DIR}/AudioAssembler.swift" \
  "${PROJECT_DIR}/AudioTimeStretcher.swift" \
  "${TESTS_DIR}/SpokenNarrationIntegration.swift" \
  -o "${TEST_ROOT}/SpokenNarrationIntegration"

LOCAL_AUDIO_PROBE_TEST_ROOT="${TEST_ROOT}" \
  "${TEST_ROOT}/SpokenNarrationIntegration"
