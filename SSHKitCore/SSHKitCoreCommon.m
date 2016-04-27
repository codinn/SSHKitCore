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

// AES BLOWFISH DES
NSString * const kVTKitDefaultEncryptionCiphers = @"aes256-ctr,aes192-ctr,aes128-ctr,aes256-cbc,aes192-cbc,aes128-cbc,blowfish-cbc,3des-cbc";

// HOSTKEYS
NSString * const kVTKitDefaultHostKeyAlgorithms = @"ssh-ed25519,ecdsa-sha2-nistp521,ecdsa-sha2-nistp384,ecdsa-sha2-nistp256,ssh-rsa,ssh-dss,ssh-rsa1";

NSString * const kVTKitDefaultMACAlgorithms = @"hmac-sha2-256,hmac-sha2-512,hmac-sha1";

// KEY_EXCHANGE
NSString * const kVTKitDefaultKeyExchangeAlgorithms = @"curve25519-sha256@libssh.org,ecdh-sha2-nistp256,diffie-hellman-group14-sha1,diffie-hellman-group1-sha1";

NSString * const kVTKitEnableCompressionKey = @"VTKitEnableCompressionKey";
NSString * const kVTKitEncryptionCiphersKey = @"VTKitEncryptionCiphersKey";
NSString * const kVTKitHostKeyAlgorithmsKey = @"VTKitHostKeyAlgorithmsKey";
NSString * const kVTKitMACAlgorithmsKey     = @"VTKitMACAlgorithmsKey";
NSString * const kVTKitKeyExchangeAlgorithmsKey = @"VTKitKeyExchangeAlgorithmsKey";
NSString * const kVTKitServerAliveCountMaxKey   = @"VTKitServerAliveCountMaxKey";


#pragma mark - Libssh logging

static void raw_session_log_callback(int priority, const char *function, const char *message, void *userdata) {
    if (!userdata) return;
    
    NSString *functionName = function ? @(function) : nil;
    NSString *messageString = message ? @(message) : nil;
    
    SSHKitLogHandler block = (__bridge SSHKitLogHandler)userdata;
    block(priority, functionName, messageString);
}

void VTKitRegisterLogCallback(NSInteger level, SSHKitLogHandler block) {
    ssh_set_log_callback(raw_session_log_callback);
    ssh_set_log_userdata((__bridge void *)(block));
    ssh_set_log_level((int)level);
}
