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

## Why chose libssh over libssh2

The [libssh](https://libssh.org/) project has nothing to do with [libssh2](https://libssh2.org/), which is a compeletly different and independent project.

At very beginning, SSHKitCore started with `libssh2`, however it quickly ran into severe limitations (at least still in version 1.7.0):

1. If your app wants to maintain multiple channels, you must open them one by one, which is inefficient
1. Suppose you are reading and writing on some opened channels, and you want to open a new shell channel on exisiting ssh session, then you must pause all of your read-write operations until shell channel is opened, otherwise your app will crash or receive malformed data
1. Not support key exchange methods like curve25519-sha256@libssh.org
1. Lacks some other algorithms support

The first two flaws can be fatal if your app provides port forwarding abilities. For example, your app maintains 2 channels for direct TCP/IP port forwarding, if target host of a channel is blocked or unreachable, then the other one is also stalled until timed out. 

On the other side, `libssh` is far more established, it's almost as full featured as OpenSSH, and doesn't have above limitations as in `libssh2`. You can open arbitrary channels simultaneously, and do the read-write operations in the meanwhile.
