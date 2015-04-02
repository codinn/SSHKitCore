//
//  SSHKitHostKeyParser.m
//  SSHKitCore
//
//  Created by Yang Yubo on 12/24/14.
//
//

#import "SSHKitHostKeyParser.h"
#import "SSHKitCore+Protected.h"

@implementation SSHKitHostKeyParser

+ (instancetype)parserFromSession:(SSHKitSession *)session error:(NSError **)errPtr {
    // --------------------------------------------------
    // get host key from session
    // --------------------------------------------------
    SSHKitHostKeyParser *parser = [[SSHKitHostKeyParser alloc] init];
    if (!parser) {
        return nil;
    }
    
    int rc = ssh_get_publickey(session.rawSession, &parser->_hostKey);
    if (rc < 0 ) {
        if (errPtr) *errPtr = [NSError errorWithDomain:SSHKitSessionErrorDomain
                                                  code:SSHKitErrorCodeHostKeyError
                                              userInfo:@{ NSLocalizedDescriptionKey : @"Cannot decode server host key" }];
        return nil;
    }
    return [parser initInfos:errPtr];
}

+ (instancetype)parserFromSSHKey:(ssh_key)sshKey error:(NSError **)errPtr {
    SSHKitHostKeyParser *parser = [[SSHKitHostKeyParser alloc] init];
    if (!parser) {
        return nil;
    }
    // memcpy(&parser->_hostKey, &sshKey, sizeof sshKey);
    parser->_hostKey = sshKey;
    parser = [parser initInfos:errPtr];
    // create a new _hostKey, org hostKey will freed by PrivateKeyParser
    ssh_pki_import_pubkey_base64([parser->_base64 cStringUsingEncoding:NSASCIIStringEncoding], (enum ssh_keytypes_e)parser->_keyType, &parser->_hostKey);
    return parser;
}

+(instancetype)parserFromFile:(NSString *)path error:(NSError *__autoreleasing *)errPtr {
    SSHKitHostKeyParser *parser = [[SSHKitHostKeyParser alloc] init];
    if (!parser) {
        return nil;
    }
    int rc = ssh_pki_import_pubkey_file(path.UTF8String, &parser->_hostKey);
    if (rc < 0 ) {
        if (errPtr) *errPtr = [NSError errorWithDomain:SSHKitSessionErrorDomain
                                                  code:SSHKitErrorCodeHostKeyError
                                              userInfo:@{ NSLocalizedDescriptionKey : @"Cannot decode public key" }];
        return nil;
    }
    return [parser initInfos:errPtr];
}

+ (instancetype)parserFromBase64:(NSString *)base64 withType:(NSInteger)type error:(NSError **)errPtr
{
    SSHKitHostKeyParser *parser = [[SSHKitHostKeyParser alloc] init];
    if (!parser) {
        return nil;
    }
    
    // --------------------------------------------------
    // set key type
    // --------------------------------------------------
    
    parser->_keyType = type;
    
    // --------------------------------------------------
    // set base64 key string
    // --------------------------------------------------
    
    parser->_base64 = [base64 copy];
    
    int rc = ssh_pki_import_pubkey_base64([parser->_base64 cStringUsingEncoding:NSASCIIStringEncoding], (enum ssh_keytypes_e)parser->_keyType, &parser->_hostKey);
    
    if (rc < 0) {
        if (errPtr) *errPtr = [NSError errorWithDomain:SSHKitSessionErrorDomain
                                             code:SSHKitErrorCodeHostKeyError
                                         userInfo:@{ NSLocalizedDescriptionKey : @"Cannot decode server host key from base64 string" }];
        return nil;
    }
    
    // --------------------------------------------------
    // success
    // --------------------------------------------------
    
    parser->_fingerprint = [self md5FingerprintForHostKey:parser->_hostKey error:errPtr];
    if (!parser->_fingerprint) {
        return nil;
    }
    
    return parser;
}

- (instancetype)initInfos:(NSError **)errPtr {
    // --------------------------------------------------
    // get key type
    // --------------------------------------------------
    _keyType = (NSInteger)ssh_key_type(_hostKey);
    
    // --------------------------------------------------
    // get base64 key string
    // --------------------------------------------------
    char *b64_key = NULL;
    int ret = ssh_pki_export_pubkey_base64(_hostKey, &b64_key);
    
    if (ret==SSH_OK) {
        _base64 = @(b64_key);
    }
    
    if (b64_key) ssh_string_free_char(b64_key);
    
    if ( !_base64.length ) {
        if (errPtr) *errPtr = [NSError errorWithDomain:SSHKitSessionErrorDomain
                                                  code:SSHKitErrorCodeHostKeyError
                                              userInfo:@{ NSLocalizedDescriptionKey :@"Cannot generate base64 string from server host key" }];
        return nil;
    }
    _fingerprint = [SSHKitHostKeyParser md5FingerprintForHostKey:_hostKey error:errPtr];
    if (!_fingerprint) {
        return nil;
    }
    return self;
}

- (NSString *)typeName
{
    return [self.class nameForKeyType:self.keyType];
}

- (NSString *)description
{
    if (!self.typeName.length) {
        return nil;
    }
    
    return [NSString stringWithFormat:@"%@ [%@]", self.fingerprint, self.typeName];
}

+ (NSString *)md5FingerprintForHostKey:(ssh_key)hostKey error:(NSError **)errPtr
{
    NSString *fingerprint = nil;
    
    unsigned char *hash = NULL;
    size_t hlen = 0;
    
    int rc = ssh_get_publickey_hash(hostKey,
                                    SSH_PUBLICKEY_HASH_MD5,
                                    &hash,
                                    &hlen);
    
    if (rc==SSH_OK) {
        char *hexa = ssh_get_hexa(hash, hlen);
        fingerprint = @(hexa);
        
        ssh_clean_pubkey_hash(&hash);
        ssh_string_free_char(hexa);
    }
    
    if (!fingerprint.length) {
        if (errPtr) *errPtr = [NSError errorWithDomain:SSHKitSessionErrorDomain
                                                  code:SSHKitErrorCodeHostKeyError
                                              userInfo:@{ NSLocalizedDescriptionKey :@"Cannot generate fingerprint from host key" }];
        return nil;
    }
    
    return fingerprint;
}

- (void)dealloc
{
    if (_hostKey) {
        // FIXME if private key freed it, will get a error.
        ssh_key_free(_hostKey);
    }
}

+ (NSString *)nameForKeyType:(NSInteger)keyType
{
    const char *name = ssh_key_type_to_char((enum ssh_keytypes_e)keyType);
    
    if (!name) {
        return nil;
    }
    
    return @(name);
}

- (void)exportPublicKey:(NSString *)path error:(NSError **)errPtr {
    // TODO write public key to file
    NSString *data = [NSString stringWithFormat:@"%@ %@", self.typeName, self.base64];
    [data writeToFile:path
              atomically:NO
                encoding:NSStringEncodingConversionAllowLossy
                   error:errPtr];
}

@end
