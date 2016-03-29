//
//  SSHKitCoreCommon.m
//  SSHKitCore
//
//  Created by Yang Yubo on 5/11/15.
//
//

#import "SSHKitCoreCommon.h"
#import <libssh/libssh.h>
#import <libssh/callbacks.h>

__attribute__((constructor))
static void SSHKitCoreInitiate() {
    static dispatch_once_t onceToken;
    
    dispatch_once(&onceToken, ^{
        dispatch_block_t block = ^{
            // use libssh with threads, GCD should be pthread based
            ssh_threads_set_callbacks(ssh_threads_get_pthread());
            ssh_init();
        };
        
        if ([NSThread isMainThread]) {
            block();
        } else {
            dispatch_sync(dispatch_get_main_queue(), block);
        }
    });
}

__attribute__((destructor))
static void SSHKitCoreFinalize() {
    static dispatch_once_t onceToken;
    
    dispatch_once(&onceToken, ^{
        dispatch_block_t block = ^{
            ssh_finalize();
        };
        
        if ([NSThread isMainThread]) {
            block();
        } else {
            dispatch_sync(dispatch_get_main_queue(), block);
        }
    });
}
