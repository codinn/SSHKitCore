//
//  Common.h
//  SSHKitCore
//
//  Created by Yang Yubo on 11/14/14.
//
//
#import <Foundation/Foundation.h>

/**
 * Seeing a return statements within an inner block
 * can sometimes be mistaken for a return point of the enclosing method.
 * This makes inline blocks a bit easier to read.
 **/
#ifndef return_from_block
#define return_from_block  return
#endif

#define SSHKitLibsshErrorDomain @"SSHKit.libssh"
#define SSHKitCoreErrorDomain   @"SSHKit.Core"
#define SSHKitSFTPErrorDomain   @"SSHKit.SFTP"
#define SSHKitSFTPRequestNotImplemented   @"SSHKit.SSHKitSFTPRequestNotImplemented"
#define SSHKitSFTPUnderlyingErrorKey      @"SSHKit.SSHKitSFTPUnderlyingErrorKey"

@class SSHKitSFTPFile;

typedef NS_ENUM(NSInteger, SSHKitErrorCode) {
    // error code from libssh
    SSHKitErrorCodeNoError        = 0,
    SSHKitErrorCodeRequestDenied,
    SSHKitErrorCodeFatal,
    SSHKitErrorCodeEINTR,
    
    // our error code
    SSHKitErrorCodeTimeout       = 1005,
    SSHKitErrorCodeHostKeyError,
    SSHKitErrorCodeAuthError,
    SSHKitErrorCodeStop,
    SSHKitErrorCodeConnectError,
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
    SSHKitChannelTypeSubsystem,     // Not supported by SSHKit framework
};

typedef NS_ENUM(NSInteger, SSHKitChannelStage) {
    SSHKitChannelStageInvalid = 0,  // channel has not been initiated correctly
    SSHKitChannelStageWating,       // channel is in the dispatch queue, and wating for opening
    SSHKitChannelStageOpening,      // channel is opening
    SSHKitChannelStageRequestPTY,   // channel is requesting a pty
    SSHKitChannelStageRequestShell, // channel is requesting a shell
    SSHKitChannelStageReadWrite,    // channel has been opened, we can read / write from the channel
    SSHKitChannelStageClosed,       // channel has been closed
};

typedef NS_ENUM(NSInteger, SSHKitSFTPClientErrorCode) {
    SSHKitSFTPClientErrorUnknown = 1,
    SSHKitSFTPClientErrorNotImplemented,
    SSHKitSFTPClientErrorOperationInProgress,
    SSHKitSFTPClientErrorInvalidHostname,
    SSHKitSFTPClientErrorInvalidUsername,
    SSHKitSFTPClientErrorInvalidPasswordOrKey,
    SSHKitSFTPClientErrorInvalidPath,
    SSHKitSFTPClientErrorAlreadyConnected,
    SSHKitSFTPClientErrorConnectionTimedOut,
    SSHKitSFTPClientErrorUnableToResolveHostname,
    SSHKitSFTPClientErrorSocketError,
    SSHKitSFTPClientErrorUnableToConnect,
    SSHKitSFTPClientErrorUnableToInitializeSession,
    SSHKitSFTPClientErrorDisconnected,
    SSHKitSFTPClientErrorHandshakeFailed,
    SSHKitSFTPClientErrorAuthenticationFailed,
    SSHKitSFTPClientErrorNotConnected,
    SSHKitSFTPClientErrorUnableToInitializSSHKitSFTP,
    SSHKitSFTPClientErrorUnableToOpenDirectory,
    SSHKitSFTPClientErrorUnableToCloseDirectory,
    SSHKitSFTPClientErrorUnableToOpenFile,
    SSHKitSFTPClientErrorUnableToCloseFile,
    SSHKitSFTPClientErrorUnableToOpenLocalFileForWriting,
    SSHKitSFTPClientErrorUnableToReadDirectory,
    SSHKitSFTPClientErrorUnableToReadFile,
    SSHKitSFTPClientErrorUnableToStatFile,
    SSHKitSFTPClientErrorUnableToCreateChannel,
    SSHKitSFTPClientErrorCancelledByUser,
    SSHKitSFTPClientErrorUnableToOpenLocalFileForReading,
    SSHKitSFTPClientErrorUnableToWriteFile,
    SSHKitSFTPClientErrorUnableToMakeDirectory,
    SSHKitSFTPClientErrorUnableToRename,
    SSHKitSFTPClientErrorUnableToRemove
};

typedef NS_ENUM(NSInteger, SSHKitSFTPRequestStatusCode) {
    // error code from libssh
    SSHKitSFTPRequestStatusWaiting  = 0,
    SSHKitSFTPRequestStatusStarted,
    SSHKitSFTPRequestStatusPaused,
    SSHKitSFTPRequestStatusCanceled,
    
    // our error code
    SSHKitSFTPRequestStatusFailed   = 1001,
};

typedef struct sftp_attributes_struct* sshkit_sftp_attributes;

/* All implementations MUST be able to process packets with an
 * uncompressed payload length of 32768 bytes or less and a total packet
 * size of 35000 bytes or less (including 'packet_length',
 *                              'padding_length', 'payload', 'random padding', and 'mac').
 */
#define SSHKIT_CORE_SSH_MAX_PAYLOAD 16384 // 16K should appropriate for both channel and sftp

typedef NSString *(^ SSHKitAskPassphrasePrivateKeyBlock)();

typedef void (^ SSHKitRequestRemoteForwardCompletionBlock)(BOOL success, uint16_t boundPort, NSError *error);

void SSHKitCoreInitiate();
void SSHKitCoreFinalize();

// Block typedefs
typedef void(^SSHKitSFTPRequestCancelHandler)(void);
typedef void(^SSHKitSFTPClientSuccessBlock)(void);
typedef void(^SSHKitSFTPClientFailureBlock)(NSError *error);
typedef void(^SSHKitSFTPClientArraySuccessBlock)(NSArray *array); // Array of SSHKitSFTPFile objects
typedef void(^SSHKitSFTPClientProgressBlock) (unsigned long long bytesReceived, unsigned long long bytesTotal);
typedef void(^SSHKitSFTPClientFileTransferSuccessBlock)(SSHKitSFTPFile *file, NSDate *startTime, NSDate *finishTime);
typedef void(^SSHKitSFTPClientFileMetadataSuccessBlock)(SSHKitSFTPFile *fileOrDirectory);
