#!/bin/zsh
set -euo pipefail

TESTS_DIR="${0:A:h}"
PROJECT_DIR="${TESTS_DIR:h}"
SDK_PATH="$(xcrun --sdk macosx --show-sdk-path)"

run_test() {
  local test_source="$1"
  local test_name="${test_source:t:r}"
  local test_root
  test_root="$(mktemp -d "/tmp/local-audio-probe-${test_name}.XXXXXX")"

  swiftc \
    -sdk "${SDK_PATH}" \
    -target arm64-apple-macos14.0 \
    -parse-as-library \
    "${PROJECT_DIR}/AppConfiguration.swift" \
    "${PROJECT_DIR}/AudioProcessing.swift" \
    "${PROJECT_DIR}/VoiceLibrary.swift" \
    "${PROJECT_DIR}/RuntimeLocator.swift" \
    "${PROJECT_DIR}/SpeechEngine.swift" \
    "${PROJECT_DIR}/NarrationSegment.swift" \
    "${PROJECT_DIR}/NarrationProject.swift" \
    "${PROJECT_DIR}/ProjectStore.swift" \
    "${PROJECT_DIR}/NarrationRules.swift" \
    "${PROJECT_DIR}/NarrationDirector.swift" \
    "${PROJECT_DIR}/GenerationJob.swift" \
    "${PROJECT_DIR}/GenerationJournal.swift" \
    "${PROJECT_DIR}/GenerationQueue.swift" \
    "${PROJECT_DIR}/AudioAssembler.swift" \
    "${PROJECT_DIR}/AudioExporter.swift" \
    "${PROJECT_DIR}/AudioTimeStretcher.swift" \
    "${PROJECT_DIR}/PlaybackController.swift" \
    "${test_source}" \
    -o "${test_root}/${test_name}"

  LOCAL_AUDIO_PROBE_TEST_ROOT="${test_root}" \
  LOCAL_AUDIO_PROBE_APP_SUPPORT="${test_root}/ApplicationSupport" \
  LOCAL_AUDIO_PROBE_OUTPUT_DIR="${test_root}/Output" \
  LOCAL_AUDIO_PROBE_TEST_FIXTURES="${TESTS_DIR}/fixtures" \
    "${test_root}/${test_name}"
}

run_test "${TESTS_DIR}/VoiceLibrarySelfTest.swift"
run_test "${TESTS_DIR}/LegacyVoiceMigrationSelfTest.swift"
run_test "${TESTS_DIR}/SpeechEngineConfigurationSelfTest.swift"
run_test "${TESTS_DIR}/ProjectStoreSelfTest.swift"
run_test "${TESTS_DIR}/ProjectMigrationSelfTest.swift"
run_test "${TESTS_DIR}/NarrationDirectorSelfTest.swift"
run_test "${TESTS_DIR}/GenerationQueueSelfTest.swift"
run_test "${TESTS_DIR}/AudioAssemblerSelfTest.swift"
run_test "${TESTS_DIR}/AudioTimeStretcherSelfTest.swift"
run_test "${TESTS_DIR}/PlaybackControllerSelfTest.swift"
