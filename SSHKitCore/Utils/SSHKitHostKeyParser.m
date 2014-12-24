//
//  SSHKitHostKeyParser.m
//  SSHKitCore
//
//  Created by Yang Yubo on 12/24/14.
//
//

#import "SSHKitHostKeyParser.h"
#import "SSHKit+Protected.h"

@implementation SSHKitHostKeyParser


- (NSError *)parseFromSession:(SSHKitSession *)session
{
    // --------------------------------------------------
    // get host key from session
    // todo: protect in session queue
    // --------------------------------------------------
    
    int rc = ssh_get_publickey(session.rawSession, &_hostKey);
    if (rc < 0) {
        NSError *error = [NSError errorWithDomain:SSHKitSessionErrorDomain
                                             code:SSHKitErrorCodeHostKeyError
                                         userInfo:@{ NSLocalizedDescriptionKey : @"Cannot decode server host key" }];
        return error;
    }
    
    // --------------------------------------------------
    // get key type
    // --------------------------------------------------
    
    _type = (SSHKitHostKeyType)ssh_key_type(_hostKey);
    
    // --------------------------------------------------
    // get base64 key string
    // --------------------------------------------------
    char *b64_key = NULL;
    int ret = ssh_pki_export_pubkey_base64(_hostKey, &b64_key);
    
    
    if (ret==SSH_OK) {
        _base64 = @(b64_key);
    }
    
    if (b64_key) ssh_string_free_char(b64_key);
    
    if (!_base64.length) {
        NSError *error = [NSError errorWithDomain:SSHKitSessionErrorDomain
                                             code:SSHKitErrorCodeHostKeyError
                                         userInfo:@{ NSLocalizedDescriptionKey :@"Cannot generate base64 string from server host key" }];
        return error;
    }
    
    // --------------------------------------------------
    // success
    // --------------------------------------------------
    
    return [self _generateMD5Fingerprint];
}

- (NSError *)parseFromBase64:(NSString *)base64 type:(SSHKitHostKeyType)type
{
    // --------------------------------------------------
    // set key type
    // --------------------------------------------------
    
    _type = type;
    
    // --------------------------------------------------
    // set base64 key string
    // --------------------------------------------------
    
    _base64 = [base64 copy];
    
    int rc = ssh_pki_import_pubkey_base64([_base64 cStringUsingEncoding:NSASCIIStringEncoding], (enum ssh_keytypes_e) _type, &_hostKey);
    
    if (rc < 0) {
        NSError *error = [NSError errorWithDomain:SSHKitSessionErrorDomain
                                             code:SSHKitErrorCodeHostKeyError
                                         userInfo:@{ NSLocalizedDescriptionKey : @"Cannot decode server host key from base64 string" }];
        return error;
    }
    
    return [self _generateMD5Fingerprint];
}

- (NSString *)typeName
{
    switch ([self type]) {
        case SSHKitHostKeyTypeDSS:
            return @"DSS";
            
        case SSHKitHostKeyTypeECDSA:
            return @"ECDSA";
            
        case SSHKitHostKeyTypeRSA:
            return @"RSA";
            
        case SSHKitHostKeyTypeRSA1:
            return @"RSA1";
            
        default:
            return @"UNKNOWN";
    }
}

- (NSError *)_generateMD5Fingerprint
{
    unsigned char *hash = NULL;
    size_t hlen = 0;
    
    int rc = ssh_get_publickey_hash(_hostKey,
                                    SSH_PUBLICKEY_HASH_MD5,
                                    &hash,
                                    &hlen);
    
    if (rc==SSH_OK) {
        char *hexa = ssh_get_hexa(hash, hlen);
        _fingerprint = @(hexa);
        
        ssh_clean_pubkey_hash(&hash);
        ssh_string_free_char(hexa);
    }
    
    if (!_fingerprint.length) {
        NSError *error = [NSError errorWithDomain:SSHKitSessionErrorDomain
                                             code:SSHKitErrorCodeHostKeyError
                                         userInfo:@{ NSLocalizedDescriptionKey :@"Cannot generate fingerprint from server host key" }];
        return error;
    }
    
    return nil;
}

- (void)dealloc
{
    if (_hostKey) {
        ssh_key_free(_hostKey);
    }
}

@end
