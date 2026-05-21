#!/bin/bash
# scripts/lib/detect_hermes_python.sh
# 共享工具：定位 Hermes 自带的 python3（venv 内置，有 PyYAML）。
# 使用方式：source 本文件后，变量 HERMES_PY 即可使用。
#
# 优先级：
#   1. ~/.hermes/hermes-agent/venv/bin/python3（Hermes 自带 venv，有 PyYAML）
#   2. hermes 可执行文件同目录下的 python3
#   3. 系统 python3（fallback，可能缺 PyYAML）

HERMES_PY="$HOME/.hermes/hermes-agent/venv/bin/python3"
if [ ! -x "$HERMES_PY" ]; then
    HERMES_PY=""
    if command -v hermes >/dev/null 2>&1; then
        HERMES_PY="$(dirname "$(command -v hermes)")/python3"
    fi
    if [ ! -x "${HERMES_PY:-}" ]; then
        HERMES_PY="$(command -v python3 || true)"
    fi
fi