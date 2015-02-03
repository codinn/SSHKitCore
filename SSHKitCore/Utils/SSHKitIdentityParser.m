//
//  SSHKitIdentityParser.m
//  SSHKitCore
//
//  Created by Yang Yubo on 12/24/14.
//
//
#import "SSHKit+Protected.h"
#import "SSHKitIdentityParser.h"

@implementation SSHKitIdentityParser

- (instancetype)initWithIdentityPath:(NSString *)path passphraseHandler:(SSHKitAskPassphrasePrivateKeyBlock)passphraseHandler
{
    if (self=[super init]) {
        _identityPath = [path copy];
        _passhpraseHandler = passphraseHandler;
    }
    
    return self;
}

- (void)dealloc
{
    if (_publicKey) {
        ssh_key_free(_publicKey);
    }
    if (_privateKey) {
        ssh_key_free(_privateKey);
    }
}

- (NSError *)parse
{
    if (!_identityPath.length) {
        NSError *error = [NSError errorWithDomain:SSHKitSessionErrorDomain
                                             code:SSHKitErrorCodeAuthError
                                         userInfo:@{ NSLocalizedDescriptionKey : @"Path of private key is not specified" }];
        return error;
    }
    
    // import private key
    int ret = ssh_pki_import_privkey_file(_identityPath.UTF8String, NULL, _askPassphrase, (__bridge void *)(_passhpraseHandler), &_privateKey);
    
    
    NSError *error = nil;
    switch (ret) {
        case SSH_OK:
            // success, try extract publickey
            break;
            
        case SSH_EOF:
            error = [NSError errorWithDomain:SSHKitSessionErrorDomain
                                        code:SSHKitErrorCodeAuthError
                                    userInfo:@{
                                               NSLocalizedDescriptionKey : [NSString stringWithFormat:@"Private key file “%@” doesn't exist or permission denied", _identityPath.lastPathComponent],
                                               NSLocalizedRecoverySuggestionErrorKey : @"Please try again or import another private key."
                                                }];
            return error;
            
        default:
            error = [NSError errorWithDomain:SSHKitSessionErrorDomain
                                        code:SSHKitErrorCodeAuthError
                                    userInfo:@{
                                               NSLocalizedDescriptionKey : [NSString stringWithFormat:@"Could not parse private key file “%@”", _identityPath.lastPathComponent],
                                               NSLocalizedRecoverySuggestionErrorKey : @"Please try again or import another private key."
                                               }];
            return error;
    }
    
    // extract public key from private key
    ret = ssh_pki_export_privkey_to_pubkey(_privateKey, &_publicKey);
    
    
    switch (ret) {
        case SSH_OK:
            // success
            break;
            
        default:
            error = [NSError errorWithDomain:SSHKitSessionErrorDomain
                                        code:SSHKitErrorCodeAuthError
                                    userInfo:@{ NSLocalizedDescriptionKey : [NSString stringWithFormat:@"Could not extract public key from \"%@\"", _identityPath] }];
            return error;;
    }
    
    return nil;
}

static int _askPassphrase(const char *prompt, char *buf, size_t len, int echo, int verify, void *userdata)
{
    if (!userdata) {
        return SSH_ERROR;
    }
    
    SSHKitAskPassphrasePrivateKeyBlock handler = (__bridge SSHKitAskPassphrasePrivateKeyBlock)userdata;
    
    if (!handler) {
        return SSH_ERROR;
    }
    
    NSString *password = handler();
    if (password.length && password.length<len) {
        strcpy(buf, password.UTF8String);
        return SSH_OK;
    }
    
    return SSH_ERROR;
}

@end
