#!/bin/zsh
set -euo pipefail

SCRIPT_DIR="${0:A:h}"
WORKSPACE_ROOT="${SCRIPT_DIR:h:h:h}"
QWEN_PROBE_ROOT="${WORKSPACE_ROOT}/spike/qwen3-mlx-python-probe"
PYTHON_EXEC_SOURCE="${QWEN_PROBE_ROOT}/.venv/bin/python"
PYTHON_HOME_SOURCE="${${PYTHON_EXEC_SOURCE}:A:h:h}"
SITE_PACKAGES_SOURCE="${QWEN_PROBE_ROOT}/.venv/lib/python3.12/site-packages"
QWEN_MODEL_SOURCE="${WORKSPACE_ROOT}/spike/models/experimental/qwen3-tts-0.6b-base-8bit"
DEEPFILTER_SOURCE="${WORKSPACE_ROOT}/spike/models/experimental/deepfilternet-mlx/v3"
DESTINATION="${1:-}"

if [[ -z "${DESTINATION}" ]]; then
  print -u2 -- "用法：package-runtime.sh <应用内 QwenRuntime 目录>"
  exit 2
fi

case "${DESTINATION}" in
  *.app/Contents/Resources/QwenRuntime) ;;
  *)
    print -u2 -- "为安全起见，运行时只能写入应用包内的 QwenRuntime 目录"
    exit 2
    ;;
esac

for required_path in \
  "${PYTHON_HOME_SOURCE}/bin/python3.12" \
  "${PYTHON_HOME_SOURCE}/lib/python3.12" \
  "${SITE_PACKAGES_SOURCE}/mlx_audio" \
  "${SITE_PACKAGES_SOURCE}/mlx" \
  "${QWEN_MODEL_SOURCE}/config.json" \
  "${DEEPFILTER_SOURCE}/model.safetensors" \
  "${SCRIPT_DIR}/Runtime/qwen_runner.py"; do
  if [[ ! -e "${required_path}" ]]; then
    print -u2 -- "缺少便携运行资源：${required_path}"
    exit 1
  fi
done

mkdir -p "${DESTINATION}"
/usr/bin/ditto --norsrc "${PYTHON_HOME_SOURCE}" "${DESTINATION}/python"
/usr/bin/ditto --norsrc \
  "${SITE_PACKAGES_SOURCE}" \
  "${DESTINATION}/python/lib/python3.12/site-packages"
cp "${SCRIPT_DIR}/Runtime/qwen_runner.py" "${DESTINATION}/qwen_runner.py"

find "${DESTINATION}" -type d -name '__pycache__' -prune -exec rm -rf {} +
find "${DESTINATION}" -type d \( -name tests -o -name test \) -prune -exec rm -rf {} +
find "${DESTINATION}" -type f \( -name '*.pyc' -o -name '*.pyo' \) -delete
rm -f \
  "${DESTINATION}/python/lib/python3.12/site-packages/_virtualenv.pth" \
  "${DESTINATION}/python/lib/python3.12/site-packages/_virtualenv.py"

PYTHON_LIBRARY="${DESTINATION}/python/lib/libpython3.12.dylib"
PYTHON_SYSCONFIG="${DESTINATION}/python/lib/python3.12/_sysconfigdata__darwin_darwin.py"
if [[ -f "${PYTHON_LIBRARY}" ]]; then
  install_name_tool -id '@rpath/libpython3.12.dylib' "${PYTHON_LIBRARY}"
fi
if [[ -f "${PYTHON_SYSCONFIG}" ]]; then
  /usr/bin/sed -i '' \
    "s|${PYTHON_HOME_SOURCE}|/Applications/LocalAudioRuntime|g" \
    "${PYTHON_SYSCONFIG}"
fi

print -r -- "${DESTINATION}"
