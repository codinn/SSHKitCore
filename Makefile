
# Comment this line to use absolute path
# CURDIR				= .

# libssh vars
LIBSSH_BASE_DIR		=	$(CURDIR)/libssh
LIBSSH_BUILD_DIR	=	$(LIBSSH_BASE_DIR)/build
LIBSSH_DIST_DIR		=	$(LIBSSH_BUILD_DIR)/dist

LIBSSH_XCODE_PROJECT=	$(LIBSSH_BUILD_DIR)/libssh.xcodeproj

# openssl vars
OPENSSL_VERSION		=	openssl-1.0.2d
OPENSSL_BASE_DIR 	=	$(CURDIR)/openssl
OPENSSL_TAR_FILE	=	$(OPENSSL_VERSION)-osx.tar.gz
OPENSSL_TAR_PATH	=	$(OPENSSL_BASE_DIR)/$(OPENSSL_TAR_FILE)
OPENSSL_DOWNLOAD_URL=	https://raw.githubusercontent.com/codinn/prebuilt-openssl/master/dist/$(OPENSSL_TAR_FILE)

OPENSSL_OSX_DIR		=	$(OPENSSL_BASE_DIR)/$(OPENSSL_VERSION)-osx
OPENSSL_OSX_LIBS	=	$(OPENSSL_OSX_DIR)/lib/libssl.a $(OPENSSL_OSX_DIR)/lib/libcrypto.a

## Download OpenSSL and generate libssh.xcodeproj automatically
all: | $(OPENSSL_TAR_PATH) $(OPENSSL_OSX_DIR) $(LIBSSH_XCODE_PROJECT)

$(OPENSSL_TAR_PATH):
	-mkdir -p $(OPENSSL_BASE_DIR)
	@echo "Downloading OpenSSL"
	@cd $(OPENSSL_BASE_DIR) && curl "$(OPENSSL_DOWNLOAD_URL)" -o "$(OPENSSL_TAR_FILE)"

$(OPENSSL_OSX_DIR):
	@echo "Unpacking OpenSSL"
	@cd $(OPENSSL_BASE_DIR) && tar xfz "$(OPENSSL_TAR_FILE)"

$(LIBSSH_XCODE_PROJECT): Makefile
	$(eval OSX_SDK := $(shell xcrun --sdk macosx --show-sdk-path))
	$(eval OSX_SDK_VERSION := $(shell xcodebuild -version -sdk macosx | grep SDKVersion | cut -f2 -d ':' | tr -d '[[:space:]]'))

	@echo "Select OS X SDK version $(OSX_SDK_VERSION)"
	@echo "Generating libssh Xcode project"
	-mkdir -p $(LIBSSH_BUILD_DIR)
	@cd $(LIBSSH_BUILD_DIR) && cmake -DOPENSSL_ROOT_DIR=$(OPENSSL_OSX_DIR) -DCMAKE_INSTALL_PREFIX=$(LIBSSH_DIST_DIR) -DWITH_PCAP=OFF -DWITH_SSH1=OFF -DWITH_STATIC_LIB=ON -DWITH_EXAMPLES=OFF -DCMAKE_MACOSX_RPATH=ON -DWITH_SERVER=ON -DCMAKE_OSX_SYSROOT=$(OSX_SDK) -DCMAKE_OSX_DEPLOYMENT_TARGET=10.9 -DCMAKE_OSX_ARCHITECTURES=x86_64 -GXcode ../

## Build libssh.xcodeproj. Usage: ``make CONFIG="Debug|Release" build``
build: | $(OPENSSL_TAR_PATH) $(OPENSSL_OSX_DIR) $(LIBSSH_XCODE_PROJECT)
	$(eval CONFIG ?= Debug)
	@echo "Building libssh with configuration $(CONFIG)"
	cd $(LIBSSH_BUILD_DIR) && xcodebuild -configuration $(CONFIG) -target install build -project libssh.xcodeproj

clean:
	@if [ -d "$(LIBSSH_BUILD_DIR)" ]; then \
		echo "Cleaning up"; \
		rm -rf $(LIBSSH_BUILD_DIR); \
	fi

## Display this help text
help: 
		$(info Available targets)
		@awk '/^[a-zA-Z\-\_0-9]+:/ {					\
		  nb = sub( /^## /, "", helpMsg );				\
		  if(nb == 0) {									\
			helpMsg = $$0;								\
			nb = sub( /^[^:]*:.* ## /, "", helpMsg );   \
		  }												\
		  if (nb)										\
			print  $$1 "\t" helpMsg;					\
		}												\
		{ helpMsg = $$0 }'								\
		$(MAKEFILE_LIST) | column -ts $$'\t' |			\
		grep --color '^[^ ]*'

# Above auto help text generate code was stolen from: https://gist.github.com/rcmachado/af3db315e31383502660 , 3rd version in the olibre's comment.

.PHONY: all clean build help
