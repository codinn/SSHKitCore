#import <Foundation/Foundation.h>

/* some types for keys */
/* same as ssh_keytypes_e from header libssh.h */
typedef NS_ENUM(NSInteger, SSHKitHostKeyType) {
    SSHKitHostKeyTypeUnknown=0,
    SSHKitHostKeyTypeDSS=1,
    SSHKitHostKeyTypeRSA,
    SSHKitHostKeyTypeRSA1,
    SSHKitHostKeyTypeECDSA,
};

/**
 * Seeing a return statements within an inner block
 * can sometimes be mistaken for a return point of the enclosing method.
 * This makes inline blocks a bit easier to read.
 **/
#ifndef return_from_block
#define return_from_block  return
#endif

#define SSHKitLibsshErrorDomain  @"SSHKit.libssh"
#define SSHKitSessionErrorDomain @"SSHKit.Session"
#define SSHKitChannelErrorDomain @"SSHKit.Channel"

typedef NS_ENUM(NSInteger, SSHKitErrorCode) {
    SSHKitErrorCodeNoError   = 0,
    SSHKitErrorCodeTimeout,
    SSHKitErrorCodeError,
    SSHKitErrorCodeHostKeyError,
    SSHKitErrorCodeAuthError,
    SSHKitErrorCodeRetry,
    SSHKitErrorCodeFatal,
};

typedef NS_ENUM(NSInteger, SSHKitPrivateKeyTestResult) {
    SSHKitPrivateKeyTestResultSuccess,
    SSHKitPrivateKeyTestResultFailed,
    SSHKitPrivateKeyTestResultMissingFile,
    SSHKitPrivateKeyTestResultUnknownError,
};

typedef int (^ SSHKitGetSocketFDBlock)(NSString *host, uint16_t port, NSError **err);

typedef NSString *(^ SSHKitAskPassphrasePrivateKeyBlock)();

#import "SSHKitSession.h"
#import "SSHKitChannel.h"
#import "SSHKitDirectChannel.h"
#import "SSHKitForwardChannel.h"

NSString * SSHKitGetNameOfHostKeyType(SSHKitHostKeyType keyType);
NSString * SSHKitGetMD5HashFromHostKey(NSString *hostKey, SSHKitHostKeyType keyType);
