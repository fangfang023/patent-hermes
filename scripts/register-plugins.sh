#!/usr/bin/env bash
set -euo pipefail

HERMES_PLUGINS_DIR="$HOME/.hermes/plugins"
PROJECT_PLUGINS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../plugins" && pwd)"

if [ ! -d "$PROJECT_PLUGINS_DIR" ]; then
  echo "[plugins] 项目 plugins/ 目录不存在，跳过注册。"
  exit 0
fi

mkdir -p "$HERMES_PLUGINS_DIR"

registered=0
skipped=0

for plugin_dir in "$PROJECT_PLUGINS_DIR"/*/; do
  [ -d "$plugin_dir" ] || continue
  plugin_name=$(basename "$plugin_dir")

  if [ ! -f "$plugin_dir/plugin.yaml" ]; then
    echo "[plugins] ⚠ $plugin_name 缺少 plugin.yaml，跳过"
    ((skipped++)) || true
    continue
  fi

  target="$HERMES_PLUGINS_DIR/$plugin_name"

  if [ -L "$target" ]; then
    current_target=$(readlink "$target")
    if [ "$current_target" = "$plugin_dir" ]; then
      echo "[plugins] ✓ $plugin_name 已注册（软链接）"
      ((skipped++)) || true
      continue
    fi
    rm -f "$target"
  elif [ -d "$target" ]; then
    echo "[plugins] $plugin_name 已存在为实体目录，替换为软链接..."
    rm -rf "$target"
  fi

  ln -s "$plugin_dir" "$target"
  echo "[plugins] ✓ $plugin_name → $plugin_dir"
  ((registered++)) || true
done

echo "[plugins] 注册完成：新增 $registered 个，跳过 $skipped 个"

# ─── 检测插件 Python 依赖 ───
SCRIPTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/detect_hermes_python.sh
. "$SCRIPTS_DIR/lib/detect_hermes_python.sh"

missing=()
for mod in fitz docx; do
  if ! "$HERMES_PY" -c "import $mod" 2>/dev/null; then
    case $mod in
      fitz) missing+=("pymupdf") ;;
      docx) missing+=("python-docx") ;;
    esac
  fi
done

if [ ${#missing[@]} -gt 0 ]; then
  echo ""
  echo "[plugins] ⚠  以下依赖未安装到 Hermes Python ($HERMES_PY)："
  for pkg in "${missing[@]}"; do
    echo "         - $pkg"
  done
  echo ""
  echo "         请执行以下命令安装："
  echo "         $HERMES_PY -m pip install ${missing[*]}"
  echo ""
fi
