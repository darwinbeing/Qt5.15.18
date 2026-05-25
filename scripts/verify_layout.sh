#!/usr/bin/env bash
#
# verify_layout.sh — confirm a self-built clang_64 has the SAME library set as
# the official open-source installer, and that every Mach-O is truly Universal.
#
# Usage: verify_layout.sh <clang_64_dir> [manifest]
#
set -euo pipefail

QTDIR="${1:?clang_64 dir required}"
# Reference: a manifest file, OR a live official Qt install dir (e.g. ~/Qt5.15.2/5.15.2/clang_64).
REF="${2:-$(cd "$(dirname "$0")" && pwd)/official_clang64.manifest}"

fail=0
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

# If REF is a directory, derive a manifest from the live official install on the fly.
if [ -d "$REF" ]; then
  echo "Reference: live official install at $REF"
  MANIFEST="$tmp/manifest"
  {
    echo "[frameworks]";   ls -d "$REF"/lib/*.framework 2>/dev/null | sed 's#.*/##; s#.framework##' | sort
    echo "[sqldrivers]";   ls "$REF"/plugins/sqldrivers 2>/dev/null | sort
    echo "[imageformats]"; ls "$REF"/plugins/imageformats 2>/dev/null | sort
    echo "[plugin_dirs]";  ls "$REF"/plugins 2>/dev/null | sort
  } > "$MANIFEST"
else
  echo "Reference: manifest $REF"
  MANIFEST="$REF"
fi

# Extract a named section ([frameworks] / [sqldrivers] / ...) from the manifest.
section() { awk -v s="[$1]" '$0==s{f=1;next} /^\[/{f=0} f&&NF{print}' "$MANIFEST"; }

cmp_set() { # <label> <expected-list-file> <actual-list-file>
  local label="$1" exp="$2" act="$3"
  local missing extra
  missing=$(comm -23 "$exp" "$act" || true)
  extra=$(comm -13 "$exp" "$act" || true)
  if [ -n "$missing" ] || [ -n "$extra" ]; then
    echo "✗ ${label}: differs from official"
    [ -n "$missing" ] && echo "    missing (official has, build lacks):" && echo "$missing" | sed 's/^/      /'
    [ -n "$extra" ]   && echo "    extra   (build has, official lacks):"  && echo "$extra"   | sed 's/^/      /'
    fail=1
  else
    echo "✓ ${label}: matches official ($(wc -l < "$exp" | tr -d ' ') items)"
  fi
}

section frameworks   | sort > "$tmp/exp_fw";  ls -d "$QTDIR"/lib/*.framework 2>/dev/null | sed 's#.*/##; s#.framework##' | sort > "$tmp/act_fw"
section sqldrivers   | sort > "$tmp/exp_sql"; ls "$QTDIR"/plugins/sqldrivers 2>/dev/null | sort > "$tmp/act_sql"
section imageformats | sort > "$tmp/exp_img"; ls "$QTDIR"/plugins/imageformats 2>/dev/null | sort > "$tmp/act_img"
section plugin_dirs  | sort > "$tmp/exp_pd";  ls "$QTDIR"/plugins 2>/dev/null | sort > "$tmp/act_pd"

cmp_set "frameworks"   "$tmp/exp_fw"  "$tmp/act_fw"
cmp_set "sqldrivers"   "$tmp/exp_sql" "$tmp/act_sql"
cmp_set "imageformats" "$tmp/exp_img" "$tmp/act_img"
cmp_set "plugin dirs"  "$tmp/exp_pd"  "$tmp/act_pd"

# Universal check: QtCore must contain both arm64 and x86_64.
core="$QTDIR/lib/QtCore.framework/QtCore"
if [ -f "$core" ]; then
  archs=$(lipo -archs "$core" 2>/dev/null || echo "?")
  if [[ "$archs" == *arm64* && "$archs" == *x86_64* ]]; then
    echo "✓ Universal: QtCore = $archs"
  else
    echo "✗ Universal: QtCore = $archs (expected arm64 + x86_64)"; fail=1
  fi
else
  echo "✗ QtCore not found at $core"; fail=1
fi

[ "$fail" -eq 0 ] && echo "ALL CHECKS PASSED" || { echo "VERIFICATION FAILED"; exit 1; }
