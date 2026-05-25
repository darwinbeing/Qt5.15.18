#!/usr/bin/env bash
#
# qt_configure.sh — run Qt 5.15.x configure with the SAME module/feature set
# as the official open-source installer, into the official directory layout.
#
# Reference (from the official Qt 5.15.2 macOS installer, clang_64):
#   - 59 frameworks, NO QtWebEngine, NO MySQL SQL driver
#   - SQL drivers on desktop  : sqlite + odbc + psql
#   - SQL drivers on mobile    : sqlite only
#   - macOS/iOS use SecureTransport (NOT OpenSSL); desktop Linux/Windows use OpenSSL
#
# The only intentional deviation from the official build is that macOS is built
# Universal (x86_64 + arm64) instead of x86_64-only.
#
# Usage:
#   qt_configure.sh <platform> <src_dir> <prefix> [deps_prefix]
#
#   platform : macos-universal | ios | android | linux
#   src_dir  : extracted qt-everywhere-... source dir
#   prefix   : install prefix, e.g. .../Qt5.15.19/5.15.19/clang_64
#   deps_prefix : (optional) prefix containing universal libpq / openssl for SQL/SSL
#
set -euo pipefail

PLATFORM="${1:?platform required}"
SRC_DIR="${2:?src_dir required}"
PREFIX="${3:?prefix required}"
DEPS_PREFIX="${4:-}"

BUILD_DIR="${SRC_DIR}/build-${PLATFORM}"
mkdir -p "${BUILD_DIR}"
cd "${BUILD_DIR}"

# ---- Options common to every platform (the official open-source module set) ----
COMMON=(
  -prefix "${PREFIX}"
  -release -opensource -confirm-license
  -nomake examples -nomake tests
  -skip qtwebengine          # official open-source installer does NOT ship WebEngine
  -no-sql-mysql              # official open-source installer does NOT ship the MySQL driver
)

# libpq (PostgreSQL) / OpenSSL headers + libs, when a deps prefix is provided
DEP_FLAGS=()
if [ -n "${DEPS_PREFIX}" ]; then
  DEP_FLAGS=( -I "${DEPS_PREFIX}/include" -L "${DEPS_PREFIX}/lib" )
fi

case "${PLATFORM}" in
  macos-universal)
    # +arm64 is the one intentional difference vs. the official x86_64-only build.
    # The official libqsqlodbc links Homebrew's keg-only iODBC, so point Qt at it.
    ODBC_FLAGS=()
    if IODBC_PREFIX=$(brew --prefix libiodbc 2>/dev/null); then
      ODBC_FLAGS=( -I "${IODBC_PREFIX}/include" -L "${IODBC_PREFIX}/lib" )
    fi
    EXTRA=(
      QMAKE_APPLE_DEVICE_ARCHS="x86_64 arm64"
      -securetransport
      -sql-sqlite -plugin-sql-odbc -plugin-sql-psql
      "${DEP_FLAGS[@]}"
      "${ODBC_FLAGS[@]}"
    )
    ;;
  ios)
    # iOS is static; mobile only ships the sqlite driver (matches official ios/).
    EXTRA=(
      -xplatform macx-ios-clang
      -static
      -securetransport
      -sql-sqlite
    )
    ;;
  android)
    # Requires ANDROID_NDK_ROOT / ANDROID_SDK_ROOT in the environment.
    EXTRA=(
      -xplatform android-clang
      -android-ndk "${ANDROID_NDK_ROOT:?ANDROID_NDK_ROOT required}"
      -android-sdk "${ANDROID_SDK_ROOT:?ANDROID_SDK_ROOT required}"
      -sql-sqlite
    )
    ;;
  linux)
    # Desktop Linux: OpenSSL (runtime-loaded, like the official installer) + full SQL set.
    EXTRA=(
      -platform linux-g++
      -openssl-runtime
      -sql-sqlite -plugin-sql-odbc -plugin-sql-psql
      "${DEP_FLAGS[@]}"
    )
    ;;
  *)
    echo "Unknown platform: ${PLATFORM}" >&2
    exit 1
    ;;
esac

echo "==> configure ${PLATFORM}"
printf '   %s\n' "${COMMON[@]}" "${EXTRA[@]}"
"${SRC_DIR}/configure" "${COMMON[@]}" "${EXTRA[@]}"
