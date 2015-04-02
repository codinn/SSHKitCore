//
//  SSHKitPrivateKeyParser.m
//  SSHKitCore
//
//  Created by Yang Yubo on 12/24/14.
//
//
#import "SSHKitCore+Protected.h"
#import "SSHKitPrivateKeyParser.h"

@implementation SSHKitPrivateKeyParser

+ (instancetype)parserFromFilePath:(NSString *)path withPassphraseHandler:(SSHKitAskPassphrasePrivateKeyBlock)passphraseHandler error:(NSError **)errPtr
{
    return [self parserFromContent:path isBase64:NO withPassphraseHandler:passphraseHandler error:errPtr];
}

+ (instancetype)parserFromBase64:(NSString *)base64 withPassphraseHandler:(SSHKitAskPassphrasePrivateKeyBlock)passphraseHandler error:(NSError **)errPtr
{
    return [self parserFromContent:base64 isBase64:YES withPassphraseHandler:passphraseHandler error:errPtr];
}


+ (instancetype)parserFromContent:(NSString *)content isBase64:(BOOL)isBase64 withPassphraseHandler:(SSHKitAskPassphrasePrivateKeyBlock)passphraseHandler error:(NSError **)errPtr
{
    if (!content.length) {
        if (errPtr) *errPtr = [NSError errorWithDomain:SSHKitSessionErrorDomain
                                                  code:SSHKitErrorCodeAuthError
                                              userInfo:@{ NSLocalizedDescriptionKey : @"Content of private key is empty" }];
        return nil;
    }
    
    int ret = 0;
    SSHKitPrivateKeyParser *parser = [[SSHKitPrivateKeyParser alloc] init];
    
    // import private key
    if (isBase64) {
        ret = ssh_pki_import_privkey_base64(content.UTF8String, NULL, _askPassphrase, (__bridge void *)(passphraseHandler), &parser->_privateKey);
    } else {
        ret = ssh_pki_import_privkey_file(content.UTF8String, NULL, _askPassphrase, (__bridge void *)(passphraseHandler), &parser->_privateKey);
    }
    
    switch (ret) {
        case SSH_OK:
            // success, try extract publickey
            break;
            
        case SSH_EOF:
            if (errPtr) *errPtr = [NSError errorWithDomain:SSHKitSessionErrorDomain
                                                      code:SSHKitErrorCodeAuthError
                                                  userInfo:@{
                                                             NSLocalizedDescriptionKey : @"Private key file doesn't exist or permission denied",
                                                             NSLocalizedRecoverySuggestionErrorKey : @"Please try again or import another private key."
                                                             }];
            return nil;
            
        default:
            if (errPtr) *errPtr = [NSError errorWithDomain:SSHKitSessionErrorDomain
                                                      code:SSHKitErrorCodeAuthError
                                                  userInfo:@{
                                                             NSLocalizedDescriptionKey : @"Could not parse private key",
                                                             NSLocalizedRecoverySuggestionErrorKey : @"Please try again or import another private key."
                                                             }];
            return nil;
    }
    
    // extract public key from private key
    ret = ssh_pki_export_privkey_to_pubkey(parser->_privateKey, &parser->_publicKey);
    
    
    switch (ret) {
        case SSH_OK:
            // success
            break;
            
        default:
            if (errPtr) *errPtr = [NSError errorWithDomain:SSHKitSessionErrorDomain
                                                      code:SSHKitErrorCodeAuthError
                                                  userInfo:@{ NSLocalizedDescriptionKey : @"Could not extract public key from private key" }];
            return nil;;
    }
    
    return parser;
}

+ (instancetype)generate:(SSHKitKeyType) type parameter:(int)param error:(NSError **)errPtr{
    SSHKitPrivateKeyParser *parser = [[SSHKitPrivateKeyParser alloc] init];
    enum ssh_keytypes_e sshKeyType = SSH_KEYTYPE_UNKNOWN;
    switch (type) {
        case SSHKitKeyTypeUnknown:
            sshKeyType = SSH_KEYTYPE_UNKNOWN;
            break;
        case SSHKitKeyTypeDSS:
            sshKeyType = SSH_KEYTYPE_DSS;
            break;
        case SSHKitKeyTypeRSA:
            sshKeyType = SSH_KEYTYPE_RSA;
            break;
        case SSHKitKeyTypeRSA1:
            sshKeyType = SSH_KEYTYPE_RSA1;
            break;
        case SSHKitKeyTypeECDSA:
            sshKeyType = SSH_KEYTYPE_ECDSA;
            break;
    }
    int ret = ssh_pki_generate(sshKeyType, param, &parser->_privateKey);
    switch (ret) {
        case SSH_OK:
            break;
        default:
            if (errPtr) *errPtr = [NSError errorWithDomain:SSHKitSessionErrorDomain
                                                      code:SSHKitErrorCodeAuthError
                                                  userInfo:@{ NSLocalizedDescriptionKey : @"Could not generate private key" }];
            return nil;;
    }
    return parser;
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
    NSUInteger length = [password lengthOfBytesUsingEncoding:NSUTF8StringEncoding];
    
    if (length && length<len) {
        strcpy(buf, password.UTF8String);
        return SSH_OK;
    }
    
    return SSH_ERROR;
}

- (void)exportPrivateKey:(NSString *)path passpharse:(NSString *)passowrd error:(NSError **)errPtr{
    // passpharse not work
    // http://www.libssh.org/archive/libssh/2015-02/0000004.html
    int ret = ssh_pki_export_privkey_file(self->_privateKey, passowrd.UTF8String, NULL, NULL, path.UTF8String);
    switch (ret) {
        case SSH_OK:
            break;
        default:
            if (errPtr) *errPtr = [NSError errorWithDomain:SSHKitSessionErrorDomain
                                                      code:SSHKitErrorCodeAuthError
                                                  userInfo:@{ NSLocalizedDescriptionKey : @"Could not export private key" }];
    }
}

- (SSHKitHostKeyParser *) publicKeyParser {
    NSError *error = nil;
    SSHKitHostKeyParser *parser = [SSHKitHostKeyParser parserFromSSHKey:self.publicKey error:&error];
    return parser;
}

@end
