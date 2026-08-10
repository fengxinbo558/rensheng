#!/bin/zsh
set -euo pipefail

SCRIPT_DIR="${0:A:h}"
PROJECT_ROOT="${SCRIPT_DIR:h:h}"
RUNTIME_ROOT="${PROJECT_ROOT}/.emotion-runtime"
SOURCE_ROOT="${RUNTIME_ROOT}/source/speech-swift"
MINIMAL_ROOT="${RUNTIME_ROOT}/speech-swift-minimal"
MINIMAL_TEMPLATE="${SCRIPT_DIR}/minimal-speech-swift-package/Package.swift"
PROBE_ROOT="${SCRIPT_DIR}/swift-probe"
EXPECTED_SPEECH_SWIFT_COMMIT="7984666dd7dc9233132c57a09bd9bf490a2ae448"
MLX_METAL_VERSION="0.31.1"
MLX_METAL_ROOT="${RUNTIME_ROOT}/mlx-metal-${MLX_METAL_VERSION}"
MLX_METALLIB="${MLX_METAL_ROOT}/mlx/lib/mlx.metallib"
UV_BIN="${PROJECT_ROOT:h:h}/qwen3-mlx-python-probe/tools/uv-aarch64-apple-darwin/uv"

mkdir -p "${RUNTIME_ROOT}/source" "${RUNTIME_ROOT}/swiftpm-cache" "${RUNTIME_ROOT}/swift-probe-build"

if [[ ! -d "${SOURCE_ROOT}/.git" ]]; then
  GIT_CONFIG_GLOBAL=/dev/null /usr/bin/git clone --filter=blob:none \
    https://github.com/soniqo/speech-swift.git "${SOURCE_ROOT}"
fi

ACTUAL_COMMIT="$(GIT_CONFIG_GLOBAL=/dev/null /usr/bin/git -C "${SOURCE_ROOT}" rev-parse HEAD)"
if [[ "${ACTUAL_COMMIT}" != "${EXPECTED_SPEECH_SWIFT_COMMIT}" ]]; then
  print -u2 -- "speech-swift 版本不一致：需要 ${EXPECTED_SPEECH_SWIFT_COMMIT}，当前 ${ACTUAL_COMMIT}"
  exit 1
fi

mkdir -p "${MINIMAL_ROOT}/Sources"
/usr/bin/ditto --norsrc "${SOURCE_ROOT}/Sources/AudioCommon" "${MINIMAL_ROOT}/Sources/AudioCommon"
/usr/bin/ditto --norsrc "${SOURCE_ROOT}/Sources/MLXCommon" "${MINIMAL_ROOT}/Sources/MLXCommon"
/usr/bin/ditto --norsrc "${SOURCE_ROOT}/Sources/CosyVoiceTTS" "${MINIMAL_ROOT}/Sources/CosyVoiceTTS"
/bin/cp "${MINIMAL_TEMPLATE}" "${MINIMAL_ROOT}/Package.swift"
/bin/cp "${SCRIPT_DIR}/minimal-speech-swift-package/OfflineModelCache.swift" \
  "${MINIMAL_ROOT}/Sources/AudioCommon/OfflineModelCache.swift"
/bin/cp "${SOURCE_ROOT}/LICENSE" "${MINIMAL_ROOT}/LICENSE"

GIT_CONFIG_GLOBAL=/dev/null /usr/bin/swift build \
  --package-path "${PROBE_ROOT}" \
  --scratch-path "${RUNTIME_ROOT}/swift-probe-build" \
  --cache-path "${RUNTIME_ROOT}/swiftpm-cache" \
  --configuration release \
  -Xswiftc -file-prefix-map \
  -Xswiftc "${PROJECT_ROOT}=." \
  -Xswiftc -debug-prefix-map \
  -Xswiftc "${PROJECT_ROOT}=." \
  -Xcc "-ffile-prefix-map=${PROJECT_ROOT}=." \
  -Xcc "-fdebug-prefix-map=${PROJECT_ROOT}=." \
  -Xcxx "-ffile-prefix-map=${PROJECT_ROOT}=." \
  -Xcxx "-fdebug-prefix-map=${PROJECT_ROOT}=." \
  --product emotion-cosy-probe

# CommandLineTools alone do not include Apple's Metal compiler. Reuse the
# version-matched precompiled MLX shader library inside the project instead of
# installing Xcode or modifying the system toolchain.
if [[ ! -s "${MLX_METALLIB}" ]]; then
  if [[ ! -x "${UV_BIN}" ]]; then
    print -u2 -- "缺少项目内依赖工具，无法准备 MLX Metal 资源：${UV_BIN}"
    exit 1
  fi
  "${UV_BIN}" pip install --no-deps --target "${MLX_METAL_ROOT}" \
    "mlx-metal==${MLX_METAL_VERSION}"
fi

if [[ ! -s "${MLX_METALLIB}" ]]; then
  print -u2 -- "MLX Metal 资源准备失败：${MLX_METALLIB}"
  exit 1
fi
/bin/cp "${MLX_METALLIB}" "${RUNTIME_ROOT}/swift-probe-build/release/mlx.metallib"

print -r -- "${RUNTIME_ROOT}/swift-probe-build/release/emotion-cosy-probe"
