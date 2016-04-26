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

#define SSHKit_SSH_OK 0     /* No error */
#define SSHKit_SSH_ERROR -1 /* Error of some kind */
#define SSHKit_SSH_AGAIN -2 /* The nonblocking call must be repeated */
#define SSHKit_SSH_EOF -127 /* We have already a eof */

@class SSHKitSFTPFile;

typedef NS_ENUM(NSInteger, SSHKitLogLevel) {
    SSHKitLogLevelNone,
    
    SSHKitLogLevelDebug,
    SSHKitLogLevelInfo,
    SSHKitLogLevelWarn,
    SSHKitLogLevelError,
    SSHKitLogLevelFatal
};

typedef NS_ENUM(NSInteger, SSHKitErrorCode) {
    // error code from libssh
    SSHKitErrorNoError        = 0,
    SSHKitErrorRequestDenied,
    SSHKitErrorFatal,
    SSHKitErrorEINTR,
    
    // our error code
    SSHKitErrorTimeout       = 1005,
    SSHKitErrorHostKeyMismatch,
    SSHKitErrorAuthFailure,
    SSHKitErrorIdentityParseFailure,
    SSHKitErrorStop,
    SSHKitErrorConnectFailure,
    SSHKitErrorChannelFailure,
};

typedef NS_ENUM(NSInteger, SSHKitProxyType) {
    SSHKitProxyTypeDirect = -1,
    SSHKitProxyTypeSOCKS5 = 0,
    SSHKitProxyTypeSOCKS4,
    SSHKitProxyTypeHTTP,
    SSHKitProxyTypeSOCKS4A,
    SSHKitProxyTypeHTTPS, // just alias of SSHKitProxyTypeHTTP
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
    SSHKitSFTPRequestStatusFinished,
    
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

typedef NSString *(^ SSHKitAskPassBlock)();
typedef NSArray *(^ SSHKitAskInteractiveInfoBlock)(NSInteger, NSString *, NSString *, NSArray *);

typedef void (^ SSHKitRequestRemoteForwardCompletionBlock)(BOOL success, uint16_t boundPort, NSError *error);

// Block typedefs
typedef void(^SSHKitSFTPRequestCancelHandler)(void);
typedef void(^SSHKitSFTPClientSuccessBlock)(void);
typedef void(^SSHKitSFTPClientFailureBlock)(NSError *error);
typedef void(^SSHKitSFTPClientArraySuccessBlock)(NSArray *array); // Array of SSHKitSFTPFile objects
typedef void(^SSHKitSFTPClientProgressBlock) (unsigned long bytesNewReceived, unsigned long long bytesReceived, unsigned long long bytesTotal);
typedef void(^SSHKitSFTPClientFolderProgressBlock) (unsigned long long filesReceived, unsigned long long filesTotal, unsigned long long bytesReceived, unsigned long long bytesTotal);
typedef void(^SSHKitSFTPClientReadFileBlock) (char *buffer, int bufferLength);
typedef void(^SSHKitSFTPClientFileTransferSuccessBlock)(SSHKitSFTPFile *file, NSDate *startTime, NSDate *finishTime);
typedef void(^SSHKitSFTPClientFileMetadataSuccessBlock)(SSHKitSFTPFile *fileOrDirectory);

// -----------------------------------------------------------------------------
#pragma mark Advanced SSH Options
// -----------------------------------------------------------------------------

extern NSString * const kVTKitEnableCompressionKey;     // @YES or @NO
extern NSString * const kVTKitEncryptionCiphersKey;
extern NSString * const kVTKitHostKeyAlgorithmsKey;
extern NSString * const kVTKitMACAlgorithmsKey;
extern NSString * const kVTKitKeyExchangeAlgorithmsKey;
extern NSString * const kVTKitServerAliveCountMaxKey;   // <=0 will disable keepalive mech.

// default preferred ciphers order
extern NSString * const kVTKitDefaultEncryptionCiphers;

// default preferred host key algorithms order
extern NSString * const kVTKitDefaultHostKeyAlgorithms;

// default preferred MAC (message authentication code) algorithms
extern NSString * const kVTKitDefaultMACAlgorithms;

// default preferred key exchange algorithms order
extern NSString * const kVTKitDefaultKeyExchangeAlgorithms;
