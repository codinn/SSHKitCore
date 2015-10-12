# SSHKitCore

SSHKitCore is an Objective-C wrapper for libssh.

## Howto Build

### 1. Generate / Regenerate libssh Xcode project file

    $ ./gen_libssh_project.sh

This script also downloads pre-built openssl automatically.

### 2. Generate libssh header files

The libssh Xcode proejct file won't generate header files automatically, you should do it by:

1. Open generated libssh.xcodeproj
2. Set build scheme to "install -> My Mac"
3. Build

You will get libssh headers and libraries after building.

### 3. Add SSHKitCore to your project
	
1. Add SSHKitCore project to your workspace or project

## Notes

1. Repeat step #1 and stpe #2 (with Clean & Build) after you have upgraded libssh or OpenSSL.
2. Execute ``./gen_libssh_project.sh clean`` if you encounter generated libssh project file was corrupted.
