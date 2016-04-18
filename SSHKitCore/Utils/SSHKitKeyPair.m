//
//  SSHKitKeyPair.m
//  SSHKitCore
//
//  Created by Yang Yubo on 12/24/14.
//
//
#import "SSHKitCore+Protected.h"
#import "SSHKitKeyPair.h"

@implementation SSHKitKeyPair

- (instancetype)initWithKeyPath:(NSString *)path withAskPass:(SSHKitAskPassBlock)askPass error:(NSError **)errPtr {
    if (!path.length) {
        if (errPtr) *errPtr = [NSError errorWithDomain:SSHKitCoreErrorDomain
                                                  code:SSHKitErrorIdentityParseFailure
                                              userInfo:@{ NSLocalizedDescriptionKey : @"Please specify a valid private key path" }];
        return nil;
    }
    
    if (self = [super init]) {
        int ret = ssh_pki_import_privkey_file(path.UTF8String, NULL, auth_callback, (__bridge void *)(askPass), &_privateKey);
        
        NSError *error = [self checkReturnCode:ret];
        if (error) {
            if (errPtr) *errPtr = error;
            return nil;
        }
        
        error = [self extractPublicKey];
        if (error) {
            if (errPtr) *errPtr = error;
            return nil;
        }
    }
    
    return self;
}

- (instancetype)initWithKeyBase64:(NSString *)base64 withAskPass:(SSHKitAskPassBlock)askPass error:(NSError **)errPtr {
    if (!base64.length) {
        if (errPtr) *errPtr = [NSError errorWithDomain:SSHKitCoreErrorDomain
                                                  code:SSHKitErrorIdentityParseFailure
                                              userInfo:@{ NSLocalizedDescriptionKey : @"Content of private key is empty" }];
        return nil;
    }
    
    if (self = [super init]) {
        int ret = ssh_pki_import_privkey_base64(base64.UTF8String, NULL, auth_callback, (__bridge void *)(askPass), &_privateKey);
        
        NSError *error = [self checkReturnCode:ret];
        if (error) {
            if (errPtr) *errPtr = error;
            return nil;
        }
        
        error = [self extractPublicKey];
        if (error) {
            if (errPtr) *errPtr = error;
            return nil;
        }
    }
    
    return self;
}

- (NSError *)checkReturnCode:(int)returnCode {
    switch (returnCode) {
        case SSH_OK:
            // success, try extract publickey
            break;
            
        case SSH_EOF:
            return [NSError errorWithDomain:SSHKitCoreErrorDomain
                                       code:SSHKitErrorIdentityParseFailure
                                   userInfo:@{
                                              NSLocalizedDescriptionKey : @"Private key file doesn't exist or permission denied",
                                              NSLocalizedRecoverySuggestionErrorKey : @"Please try again or import another private key."
                                              }];
            
        default:
            return [NSError errorWithDomain:SSHKitCoreErrorDomain
                                       code:SSHKitErrorIdentityParseFailure
                                   userInfo:@{
                                              NSLocalizedDescriptionKey : @"Could not parse private key",
                                              NSLocalizedRecoverySuggestionErrorKey : @"Please try again or import another private key."
                                              }];
    }
    
    return nil;
}


- (NSError *)extractPublicKey {
    // extract public key from private key
    int ret = ssh_pki_export_privkey_to_pubkey(_privateKey, &_publicKey);
    
    switch (ret) {
        case SSH_OK:
            // success
            break;
            
        default:
            return [NSError errorWithDomain:SSHKitCoreErrorDomain
                                       code:SSHKitErrorIdentityParseFailure
                                   userInfo:@{ NSLocalizedDescriptionKey : @"Could not extract public key from private key" }];
    }
    
    return nil;
}

- (void)dealloc {
    if (_publicKey) {
        ssh_key_free(_publicKey);
    }
    if (_privateKey) {
        ssh_key_free(_privateKey);
    }
}

static int auth_callback(const char *prompt, char *buf, size_t len, int echo, int verify, void *userdata) {
    if (!userdata) {
        return SSH_ERROR;
    }
    
    SSHKitAskPassBlock handler = (__bridge SSHKitAskPassBlock)userdata;
    
    if (!handler) {
        return SSH_ERROR;
    }
    
    NSString *password = handler();
    NSUInteger length = [password lengthOfBytesUsingEncoding:NSUTF8StringEncoding];
    
    if (length && length<len) {
        strcpy(buf, password.UTF8String);
        return SSH_OK;
    }
    
    return SSH_ERROR;
}

@end
