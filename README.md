# SSHKitCore

SSHKitCore is an Objective-C wrapper for libssh.

## Generate / Regenerate libssh Xcode project file

	$ ./gen_libssh_project.sh

This script also downloads and builds openssl automatically.

## Add SSHKitCore to your project
	
1. Add SSHKitCore project to your workspace or project
1. Add `ssh_static` and `ssh_threads_static` to your project's "Target Dependencies" list
1. Add `libssh.a` and `libssh_threads.a` to your project's "Link Binary With Libraries" list
1. Add `$(SRCROOT)/libssh/build/dist/include` to your project's "Header Search Paths" list

## Generate libssh header files

The libssh Xcode proejct file won't generate header files automatically, you should do it by setting build scheme to "install -> My Mac (64-bit)".

You will get libssh headers after build (just ignore the compiler warnings and errors).

## Build with SSHKitCore

Set build scheme back to your project scheme, clean before build.
