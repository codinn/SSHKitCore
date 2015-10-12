#!/bin/bash

BASE_DIR=`pwd`

pushd .

BUILD_DIR="$BASE_DIR/libssh/build/"

if [[ "$1" == "clean" ]]; then
	echo "Cleaning up"
	rm -rf ${BUILD_DIR}
fi

mkdir -p ${BUILD_DIR}

cd ${BUILD_DIR}

OPENSSL_VERSION="openssl-1.0.2d"

OPENSSL_FILE="${OPENSSL_VERSION}-osx.tar.gz"
OPENSSL_URL="https://raw.githubusercontent.com/codinn/prebuilt-openssl/master/dist/${OPENSSL_FILE}"

if [ ! -e "${OPENSSL_FILE}" ]; then
	curl "${OPENSSL_URL}" -o "${OPENSSL_FILE}"
else
   echo "Using ${OPENSSL_FILE}"
fi

echo "Unpacking OpenSSL"
tar xfz "${OPENSSL_FILE}"

OSX_SDK=$(xcrun --sdk macosx --show-sdk-path)

# always regenerate project file
rm -f CMakeCache.txt
cmake -DCMAKE_PREFIX_PATH=${BUILD_DIR}/${OPENSSL_VERSION}-osx -DOPENSSL_ROOT_DIR= -DCMAKE_INSTALL_PREFIX=./dist -DCMAKE_BUILD_TYPE=MinSizeRel -DWITH_SSH1=OFF -DWITH_STATIC_LIB=ON -DWITH_EXAMPLES=OFF -DCMAKE_MACOSX_RPATH=ON -DWITH_SERVER=ON -DCMAKE_OSX_SYSROOT=${OSX_SDK} -DCMAKE_OSX_DEPLOYMENT_TARGET=10.9 -DCMAKE_OSX_ARCHITECTURES=x86_64 -GXcode ../
popd
