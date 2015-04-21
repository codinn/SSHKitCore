//
//  SSHKitPrivateKeyParser.m
//  SSHKitCore
//
//  Created by Yang Yubo on 12/24/14.
//
//
#import "SSHKitCore+Protected.h"
#import "SSHKitPrivateKeyParser.h"
#import <CommonCrypto/CommonDigest.h>
#include <openssl/rsa.h>
#include <openssl/dsa.h>
#include <openssl/sha.h>
#include <openssl/pem.h>

#define INTBLOB_LEN	20
#define SIGBLOB_LEN	(2*INTBLOB_LEN)

int bufferAddSshString(NSMutableData *buffer, ssh_string string) {
    //ntohl
    uint32_t len = (uint32_t)ssh_string_len(string);
    [buffer appendBytes:string length:len + sizeof(uint32_t)];
    return 0;
}

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
    if (_privateKey) {
        ssh_key_free(_privateKey);
    }
    if (_publicKey) {
        ssh_key_free(_publicKey);
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

- (SSHKitHostKeyParser *)publicKeyParser {
    NSError *error = nil;
    SSHKitHostKeyParser *parser = [SSHKitHostKeyParser parserFromSSHKey:self.publicKey error:&error];
    return parser;
}


- (NSData *)exportBlob {
    NSMutableData *data = [NSMutableData data];
    ssh_string blob = pki_publickey_to_blob(self.privateKey);
    if (!blob) {
        return nil;
    }
    bufferAddSshString(data, blob);
    ssh_string_free(blob);
    // TODO get comment
    ssh_string comment = ssh_string_new(0);
    bufferAddSshString(data, comment);
    return data;
}

- (NSData *)signWithSHA128:(NSData *)message error:(NSError **)error
{
    SHA_CTX shaCtx;
    unsigned char messageDigest[SHA_DIGEST_LENGTH];
    if (!SHA1_Init(&shaCtx)) {
        // if (error) *error = [NSError errorFromOpenSSL];
        return nil;
    }
    if (!SHA1_Update(&shaCtx, message.bytes, message.length)) {
        // if (error) *error = [NSError errorFromOpenSSL];
        return nil;
    }
    if (!SHA1_Final(messageDigest, &shaCtx)) {
        // if (error) *error = [NSError errorFromOpenSSL];
        return nil;
    }
    
    NSMutableData *signature = [NSMutableData dataWithLength:(NSUInteger) RSA_size(self.privateKey->rsa)];
    unsigned int signatureLength = 0;
    if (RSA_sign(NID_sha1, messageDigest, SHA_DIGEST_LENGTH, signature.mutableBytes, &signatureLength, self.privateKey->rsa) == 0) {
        // if (error) *error = [NSError errorFromOpenSSL];
        return nil;
    }
    [signature setLength:(NSUInteger) signatureLength];
    
    return signature;
}

- (NSData *)signDSS:(NSData *)message error:(NSError **)error
{
    SHA_CTX shaCtx;
    DSA_SIG *sig = NULL;
    unsigned char messageDigest[SHA_DIGEST_LENGTH];
    if (!SHA1_Init(&shaCtx)) {
        // if (error) *error = [NSError errorFromOpenSSL];
        return nil;
    }
    if (!SHA1_Update(&shaCtx, message.bytes, message.length)) {
        // if (error) *error = [NSError errorFromOpenSSL];
        return nil;
    }
    if (!SHA1_Final(messageDigest, &shaCtx)) {
        // if (error) *error = [NSError errorFromOpenSSL];
        return nil;
    }
    
    unsigned int signatureLength = 0;
    if ((sig = DSA_do_sign(messageDigest, SHA_DIGEST_LENGTH, self.privateKey->dsa)) == NULL) {
        // if (error) *error = [NSError errorFromOpenSSL];
        return nil;
    }
    size_t rlen, slen;
    rlen = BN_num_bytes(sig->r);
    slen = BN_num_bytes(sig->s);
    if (rlen > INTBLOB_LEN || slen > INTBLOB_LEN) {
        return nil;
    }
    NSMutableData *sigblob = [NSMutableData dataWithLength:(NSUInteger) SIGBLOB_LEN];
    BN_bn2bin(sig->r, sigblob.bytes + SIGBLOB_LEN - INTBLOB_LEN - rlen);
    BN_bn2bin(sig->s, sigblob.bytes + SIGBLOB_LEN - slen);
    // TODO compat
    return sigblob;
}

- (NSData *)sign:(NSData *)data compat:(NSUInteger)compat {
    //pki_do_sign_sessionid
    switch (self.privateKey->type) {
        case SSH_KEYTYPE_RSA:
            break;
        case SSH_KEYTYPE_RSA1:
            break;
        case SSH_KEYTYPE_DSS:
            break;
        default:
            break;
    }
    switch (self.privateKey->type) {
        case SSH_KEYTYPE_ECDSA:
            break;
        case SSH_KEYTYPE_RSA:
        case SSH_KEYTYPE_RSA1: {
            NSMutableData *d = [NSMutableData data];
            uint32_t size = htonl(strlen("ssh-rsa"));
            [d appendBytes:&size length:sizeof(uint32_t)];
            [d appendData:[@"ssh-rsa" dataUsingEncoding:NSASCIIStringEncoding]];
            NSData *sign = [self signWithSHA128:data error:nil];
            size = htonl(sign.length);
            [d appendBytes:&size length:sizeof(uint32_t)];
            [d appendData:sign];
            return d;
        }
        case SSH_KEYTYPE_DSS: {
            NSMutableData *d = [NSMutableData data];
            uint32_t size = htonl(strlen("ssh-dss"));
            [d appendBytes:&size length:sizeof(uint32_t)];
            [d appendData:[@"ssh-dss" dataUsingEncoding:NSASCIIStringEncoding]];
            NSData *sign = [self signDSS:data error:nil];
            size = htonl(sign.length);
            [d appendBytes:&size length:sizeof(uint32_t)];
            [d appendData:sign];
            return d;
        }
        default:
            break;
    }
    return nil;
}

@end