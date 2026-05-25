#!/usr/bin/env bash
#
# patch_qt_src.sh — minimal source fixes so Qt 5.15.x compiles under modern
# clang/libc++ (clang 15+, the only toolchain available on current GitHub
# macOS runners). Idempotent: safe to run more than once.
#
# Usage: patch_qt_src.sh <qt_src_dir>
#
set -euo pipefail
SRC="${1:?qt src dir required}"

# qtlocation's bundled mapbox-gl-native uses std::move in unique_any.hpp but
# only includes <type_traits>. Newer libc++ no longer pulls in <utility>
# transitively, so std::move is undeclared -> "no member named 'move' in
# namespace 'std'". Add the include.
ua="$SRC/qtlocation/src/3rdparty/mapbox-gl-native/include/mbgl/util/unique_any.hpp"
if [ -f "$ua" ] && ! grep -q '#include <utility>' "$ua"; then
  perl -0pi -e 's/#include <type_traits>/#include <type_traits>\n#include <utility>/' "$ua"
  echo "patched: <utility> added to $(basename "$ua")"
fi
