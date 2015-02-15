# SSHKitCore

SSHKitCore is an Objective-C wrapper for libssh.

## 1. Generate / Regenerate libssh Xcode project file

    $ ./gen_libssh_project.sh

This script also downloads and builds openssl automatically.

## 2. Generate libssh header files

The libssh Xcode proejct file won't generate header files automatically, you should do it by:

1. Open generated libssh.xcodeproj
2. Set build scheme to "install -> My Mac (64-bit)"
3. Build

You will get libssh headers after building.

## 3. Add SSHKitCore to your project
	
1. Add SSHKitCore project to your workspace or project
