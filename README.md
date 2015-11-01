# SSHKitCore

SSHKitCore is an Objective-C wrapper for libssh.

## Prerequisites

Libssh requires [CMake](https://cmake.org/) for building, you can install CMake through [Homebrew](http://brew.sh/):

```
# Install homebrew if if you hadn't already installed it
ruby -e "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/master/install)"

# Install CMake through Homebrew
brew update && brew install CMake
```

## Build

1. Add SSHKitCore project to your workspace or project
1. Add SSHKitCore to your workspace or project dependencies and linking libraries
1. You will get a linkage error message when you build for the first time:
```
ld: library not found for -lssh_threads
clang: error: linker command failed with exit code 1 (use -v to see invocation)
```
1. The reason for the error is because ``libssh.xcodeproj`` wasn't created untill first build finished. So just close and reopen your workspace or project, the error message should disappear if you build again

### Troubleshooting

The generated ``libssh.xcodeproj`` does not support build location automatic realocate, so then building of ``libssh.xcodeproj`` is primary drove by ``SSHKitCore/Makefile``
	
If your ``libssh.xcodeproj`` was corrupted, or encounter other libssh compilation error, you can execute ``make clean && make`` command to force a fresh ``libssh.xcodeproj`` generating.

### Note

``SSHKitCore/Makefile`` also downloads a pre-built openssl to ``SSHKitCore/openssl`` directory automatically.

Execute ``make help`` will reveal all targets and their help texts.
