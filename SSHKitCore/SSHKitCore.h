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

typedef int (^ SSHKitGetSocketFDBlock)(NSString *host, uint16_t port, NSError **err);

typedef NSString *(^ SSHKitAskPassphrasePrivateKeyBlock)();

#import "SSHKitSession.h"
#import "SSHKitChannel.h"
#import "SSHKitDirectTCPIPChannel.h"

NSString * SSHKitGetNameOfHostKeyType(SSHKitHostKeyType keyType);
NSString * SSHKitGetMD5HashFromHostKey(NSString *hostKey, SSHKitHostKeyType keyType);
