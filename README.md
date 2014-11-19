# SSHKit

SSHKit is an Objective-C wrapper for libssh.

## Build


### Build openssl

	$ cd openssl
	$ ./openssl-build.sh

## Generate libssh Xcode project file

	$ cd build
	$ cmake -DCMAKE_PREFIX_PATH=$(PWD)/../../openssl/dist/openssl-1.0.1j-MacOSX -DOPENSSL_ROOT_DIR= -DCMAKE_INSTALL_PREFIX=./dist -DCMAKE_BUILD_TYPE=MinSizeRel -DWITH_SSH1=OFF -DWITH_STATIC_LIB=ON -DWITH_SERVER=ON -MACOSX_DEPLOYMENT_TARGET=10.9 -DCMAKE_OSX_SYSROOT=/Applications/Xcode.app/Contents/Developer/Platforms/MacOSX.platform/Developer/SDKs/MacOSX10.9.sdk/ -GXcode ../
	$ make install

## Build SSHKit

TODO...
