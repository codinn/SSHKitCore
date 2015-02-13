//
//  Common.h
//  SSHKitCore
//
//  Created by Yang Yubo on 11/14/14.
//
//
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
#define SSHKIT_REMOTE_FORWARD_COMPLETE_NOTIFICATION @"com.codinn.sshkit.remote-forward.complete.notification"

typedef NS_ENUM(NSInteger, SSHKitErrorCode) {
    SSHKitErrorCodeNoError   = 0,
    SSHKitErrorCodeTimeout,
    SSHKitErrorCodeError,
    SSHKitErrorCodeHostKeyError,
    SSHKitErrorCodeAuthError,
    SSHKitErrorCodeRetry,
    SSHKitErrorCodeFatal,
};

typedef NS_ENUM(NSInteger, SSHKitProxyType) {
    SSHKitProxyTypeDirect = -1,
    SSHKitProxyTypeSOCKS5 = 0,
    SSHKitProxyTypeSOCKS4,
    SSHKitProxyTypeHTTP,
    SSHKitProxyTypeSOCKS4A,
    SSHKitProxyTypeHTTPS, // just alias of SSHKitProxyTypeHTTP
};

typedef NS_ENUM(NSInteger, SSHKitChannelType)  {
    SSHKitChannelTypeUnknown = 0,
    SSHKitChannelTypeDirect,
    SSHKitChannelTypeForward,
    SSHKitChannelTypeExec,
    SSHKitChannelTypeShell,
    SSHKitChannelTypeSCP,
    SSHKitChannelTypeSubsystem // Not supported by SSHKit framework
};

typedef NS_ENUM(NSInteger, SSHKitAuthMethodType) {
    SSHKitAuthMethodTypeUnknown     = -2,
    SSHKitAuthMethodTypeNone        = -1,
    SSHKitAuthMethodTypePassword    = 0,
    SSHKitAuthMethodTypePublicKey,
    SSHKitAuthMethodTypeInteractive,
    SSHKitAuthMethodTypeHostBased,
    SSHKitAuthMethodTypeGSSAPI,
};

typedef NS_ENUM(NSInteger, SSHKitChannelStage) {
    SSHKitChannelStageInvalid,        // channel has not been inited correctly
    SSHKitChannelStageCreated,        // channel has been created
    SSHKitChannelStageOpening,        // the channel is opening
    SSHKitChannelStageReadWrite,      // the channel has been opened, we can read / write from the channel
    SSHKitChannelStageClosed,         // the channel has been closed
};

/* All implementations MUST be able to process packets with an
 * uncompressed payload length of 32768 bytes or less and a total packet
 * size of 35000 bytes or less (including 'packet_length',
 *                              'padding_length', 'payload', 'random padding', and 'mac').
 */
#define SSHKIT_CORE_SSH_MAX_PAYLOAD 16384 // 16K should appropriate for both channel and sftp

typedef NSString *(^ SSHKitAskPassphrasePrivateKeyBlock)();

typedef void (^ SSHKitRequestRemoteForwardCompletionBlock)(BOOL success, uint16_t boundPort, NSError *error);
