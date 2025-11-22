#!/bin/bash
set -e

# ======================================================
# Universal dependency builder for Qt 5.15.x
# Builds:
#   - OpenSSL 1.1.1w (universal)
#   - MySQL Client 8.0.39 (universal)
#
# Output:
#   $PREFIX/include
#   $PREFIX/lib
# ======================================================

PREFIX="$1"

if [ -z "$PREFIX" ]; then
  echo "Usage: build_deps.sh <install_prefix>"
  exit 1
fi

mkdir -p "$PREFIX"
WORKDIR=$(pwd)


#!/usr/bin/env bash
set -e

OPENSSL_VERSION="1.1.1w"
MYSQL_VERSION="8.0.39"
PG_VERSION="14.7"

DEPS_DIR="$PREFIX"
OPENSSL_PREFIX="$PREFIX"
MYSQL_PREFIX="$PREFIX"
PG_PREFIX="$PREFIX"

#######################################
# Build OpenSSL universal
#######################################
build_openssl() {
    echo "==== Building OpenSSL universal ===="
    cd "$DEPS_DIR"
    if [ ! -d openssl-src ]; then
        curl -LO https://www.openssl.org/source/openssl-$OPENSSL_VERSION.tar.gz
        tar xf openssl-$OPENSSL_VERSION.tar.gz
        mv openssl-$OPENSSL_VERSION openssl-src
    fi

    cd openssl-src
    for ARCH in x86_64 arm64; do
        ./Configure darwin64-${ARCH}-cc no-shared --prefix="$PWD/build-$ARCH"
        make clean
        make -j$(sysctl -n hw.ncpu)
        make install_sw
    done

    mkdir -p "$OPENSSL_PREFIX/lib" "$OPENSSL_PREFIX/include"
    lipo -create build-x86_64/lib/libssl.a \
	 build-arm64/lib/libssl.a \
	 -output "$OPENSSL_PREFIX/lib/libssl.a"
    lipo -create build-x86_64/lib/libcrypto.a \
	 build-arm64/lib/libcrypto.a \
	 -output "$OPENSSL_PREFIX/lib/libcrypto.a"
    cp -R build-arm64/include/* "$OPENSSL_PREFIX/include"

    echo "==== OpenSSL universal ready ===="
}

#######################################
# Build MySQL universal
#######################################
build_mysql() {
    echo "==== Building MySQL universal ===="
    cd "$DEPS_DIR"
    if [ ! -d mysql-src ]; then
        curl -LO https://dev.mysql.com/get/Downloads/MySQL-8.0/mysql-boost-$MYSQL_VERSION.tar.gz
        tar xf mysql-boost-$MYSQL_VERSION.tar.gz
        mv mysql-$MYSQL_VERSION mysql-src
    fi

    # ARM64
    mkdir -p mysql-build-arm64
    cd mysql-build-arm64
    cmake ../mysql-src \
        -DCMAKE_INSTALL_PREFIX="$MYSQL_PREFIX/arm64" \
        -DCMAKE_OSX_ARCHITECTURES=arm64 \
        -DWITH_SSL="$OPENSSL_PREFIX" \
        -DWITHOUT_SERVER=ON
    make -j$(sysctl -n hw.ncpu)
    make install

    # x86_64
    cd "$DEPS_DIR"
    mkdir -p mysql-build-x64
    cd mysql-build-x64
    cmake ../mysql-src \
        -DCMAKE_INSTALL_PREFIX="$MYSQL_PREFIX/x86_64" \
        -DCMAKE_OSX_ARCHITECTURES=x86_64 \
        -DWITH_SSL="$OPENSSL_PREFIX" \
        -DWITHOUT_SERVER=ON
    make -j$(sysctl -n hw.ncpu)
    make install

    # Merge MySQL
    for lib in libmysqlclient.a libmysqlclient.dylib; do
        lipo -create \
            "$MYSQL_PREFIX/arm64/lib/$lib" \
            "$MYSQL_PREFIX/x86_64/lib/$lib" \
            -output "$MYSQL_PREFIX/lib/$lib"
    done
    cp -R "$MYSQL_PREFIX/arm64/include/"* "$MYSQL_PREFIX/include/"

    echo "==== MySQL universal ready ===="
}

#######################################
# Build PostgreSQL universal
#######################################
build_postgresql() {
    echo "==== Building PostgreSQL universal ===="
    cd "$DEPS_DIR"
    if [ ! -d postgresql-src ]; then
        curl -LO https://ftp.postgresql.org/pub/source/v$PG_VERSION/postgresql-$PG_VERSION.tar.gz
        tar xf postgresql-$PG_VERSION.tar.gz
        mv postgresql-$PG_VERSION postgresql-src
    fi
    cd postgresql-src
      CFLAGS="-arch x86_64 -arch arm64" \
      ./configure --with-ssl=openssl --prefix="$PG_PREFIX" \
      --with-includes="$OPENSSL_PREFIX"/include --with-libraries="$OPENSSL_PREFIX"/lib

    make -j$(sysctl -n hw.ncpu)
    make install

    echo "==== PostgreSQL universal ready ===="
}

#######################################
# Call all dependency builds
#######################################
build_deps() {
    build_openssl
    # build_mysql
    build_postgresql
    echo "==== All dependencies built successfully ===="
    echo "OpenSSL: $OPENSSL_PREFIX"
    echo "MySQL: $MYSQL_PREFIX"
    echo "PostgreSQL: $PG_PREFIX"
}

build_deps
