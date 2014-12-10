//
//  SSHKit.m
//  SSHKit
//
//  Created by Yang Yubo on 11/14/14.
//
//

#import <Foundation/Foundation.h>
#import <libssh/libssh.h>
#import "SSHKitCore.h"


NSString * SSHKitGetNameOfHostKeyType(SSHKitHostKeyType keyType)
{
    switch (keyType) {
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

NSString * SSHKitGetBase64FromHostKey(ssh_key key)
{
    char *b64_key = NULL;
    int ret = ssh_pki_export_pubkey_base64(key, &b64_key);
    
    NSString *b64Key = nil;
    
    if (ret==SSH_OK) {
        b64Key = @(b64_key);
    }
    
    if (b64_key) ssh_string_free_char(b64_key);
    
    return b64Key;
}

NSString * SSHKitGetMD5HashFromHostKey(NSString *hostKey, SSHKitHostKeyType keyType)
{
    ssh_key pkey;
    enum ssh_keytypes_e key_type = (enum ssh_keytypes_e) keyType;
    
    int ret = ssh_pki_import_pubkey_base64([hostKey cStringUsingEncoding:NSASCIIStringEncoding], key_type, &pkey);
    
    NSString *md5Hash = nil;
    
    if (ret==SSH_OK) {
        unsigned char *hash = NULL;
        size_t hlen = 0;
        
        int rc = ssh_get_publickey_hash(pkey,
                                    SSH_PUBLICKEY_HASH_MD5,
                                    &hash,
                                    &hlen);
        
        if (rc==SSH_OK) {
            char *hexa = ssh_get_hexa(hash, hlen);
            md5Hash = @(hexa);
            
            ssh_clean_pubkey_hash(&hash);
            ssh_string_free_char(hexa);
        }
    }
    
    ssh_key_free(pkey);
    return md5Hash;
}
