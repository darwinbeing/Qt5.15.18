#!/usr/bin/env bash
#
# fix_lib.sh — rewrite leaked absolute dependency paths in an installed Qt tree
# to @loader_path so the SQL drivers (and anything linking our universal deps)
# load on machines other than the build runner.
#
# This is a thin wrapper around find_lib_dep.py; it defaults to the macOS
# desktop install layout but accepts the Qt dir as $1.
#
# Usage: fix_lib.sh [qt_dir] [deps_lib_dir]
#
set -euo pipefail

QT_DIR="${1:-$HOME/Qt5.15.19/5.15.19/clang_64}"
DEPS_LIB="${2:-}"

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

args=("$QT_DIR")
[ -n "$DEPS_LIB" ] && args+=(--deps-lib "$DEPS_LIB")

python3 "${SCRIPT_DIR}/find_lib_dep.py" "${args[@]}"
