#!/bin/zsh
set -euo pipefail

TESTS_DIR="${0:A:h}"
PROJECT_DIR="${TESTS_DIR:h}"
SDK_PATH="$(xcrun --sdk macosx --show-sdk-path)"
QWEN_PYTHON="${PROJECT_DIR:h:h}/qwen3-mlx-python-probe/.venv/bin/python"

if [[ ! -x "${QWEN_PYTHON}" ]]; then
  print -u2 -- "缺少本地自然人声测试运行程序：${QWEN_PYTHON}"
  exit 1
fi

"${QWEN_PYTHON}" "${PROJECT_DIR}/Runtime/qwen_runner_smoke.py"

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
    "${PROJECT_DIR}/QwenSpeechEngine.swift" \
    "${PROJECT_DIR}/DeviceSynthesisPolicy.swift" \
    "${PROJECT_DIR}/NarrationSegment.swift" \
    "${PROJECT_DIR}/EmotionInstructionBuilder.swift" \
    "${PROJECT_DIR}/NarrationProject.swift" \
    "${PROJECT_DIR}/ContentImporter.swift" \
    "${PROJECT_DIR}/PlainTextImporter.swift" \
    "${PROJECT_DIR}/PDFTextImporter.swift" \
    "${PROJECT_DIR}/ContentImportCoordinator.swift" \
    "${PROJECT_DIR}/WebArticleExtractionHost.swift" \
    "${PROJECT_DIR}/WebArticleImporter.swift" \
    "${PROJECT_DIR}/SpokenScriptValidator.swift" \
    "${PROJECT_DIR}/SpokenScriptDirector.swift" \
    "${PROJECT_DIR}/ProjectStore.swift" \
    "${PROJECT_DIR}/NarrationRules.swift" \
    "${PROJECT_DIR}/NarrationDirector.swift" \
    "${PROJECT_DIR}/GenerationJob.swift" \
    "${PROJECT_DIR}/GenerationJournal.swift" \
    "${PROJECT_DIR}/GenerationQueue.swift" \
    "${PROJECT_DIR}/AudioAssembler.swift" \
    "${PROJECT_DIR}/AvailableAudioBuilder.swift" \
    "${PROJECT_DIR}/AudioExporter.swift" \
    "${PROJECT_DIR}/AudioTimeStretcher.swift" \
    "${PROJECT_DIR}/PlaybackController.swift" \
    "${test_source}" \
    -framework PDFKit \
    -framework CoreText \
    -framework WebKit \
    -o "${test_root}/${test_name}"

  LOCAL_AUDIO_PROBE_TEST_ROOT="${test_root}" \
  LOCAL_AUDIO_PROBE_APP_SUPPORT="${test_root}/ApplicationSupport" \
  LOCAL_AUDIO_PROBE_OUTPUT_DIR="${test_root}/Output" \
  LOCAL_AUDIO_PROBE_TEST_FIXTURES="${TESTS_DIR}/fixtures" \
  LOCAL_AUDIO_PROBE_PROJECT_DIR="${PROJECT_DIR}" \
    "${test_root}/${test_name}"
}

run_test "${TESTS_DIR}/VoiceLibrarySelfTest.swift"
run_test "${TESTS_DIR}/LegacyVoiceMigrationSelfTest.swift"
run_test "${TESTS_DIR}/SpeechEngineConfigurationSelfTest.swift"
run_test "${TESTS_DIR}/QwenWorkerSelfTest.swift"
run_test "${TESTS_DIR}/DeviceSynthesisPolicySelfTest.swift"
run_test "${TESTS_DIR}/EmotionInstructionBuilderSelfTest.swift"
run_test "${TESTS_DIR}/ProjectStoreSelfTest.swift"
run_test "${TESTS_DIR}/ProjectMigrationSelfTest.swift"
run_test "${TESTS_DIR}/ContentImporterSelfTest.swift"
run_test "${TESTS_DIR}/PDFTextImporterSelfTest.swift"
run_test "${TESTS_DIR}/ContentImportCoordinatorSelfTest.swift"
run_test "${TESTS_DIR}/WebArticleImporterSelfTest.swift"
run_test "${TESTS_DIR}/SpokenScriptValidatorSelfTest.swift"
run_test "${TESTS_DIR}/SpokenScriptDirectorSelfTest.swift"
run_test "${TESTS_DIR}/NarrationDirectorSelfTest.swift"
run_test "${TESTS_DIR}/GenerationQueueSelfTest.swift"
run_test "${TESTS_DIR}/AudioAssemblerSelfTest.swift"
run_test "${TESTS_DIR}/AvailableAudioBuilderSelfTest.swift"
run_test "${TESTS_DIR}/AudioTimeStretcherSelfTest.swift"
run_test "${TESTS_DIR}/PlaybackControllerSelfTest.swift"
