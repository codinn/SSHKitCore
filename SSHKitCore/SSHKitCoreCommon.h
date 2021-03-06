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
#define SSHKitLibsshSFTPErrorDomain @"SSHKit.libssh.SFTP"
#define SSHKitCoreErrorDomain   @"SSHKit.Core"

#define SSHKit_SSH_OK 0     /* No error */
#define SSHKit_SSH_ERROR -1 /* Error of some kind */
#define SSHKit_SSH_AGAIN -2 /* The nonblocking call must be repeated */
#define SSHKit_SSH_EOF -127 /* We have already a eof */

@class SSHKitSFTPFile;

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

typedef NS_ENUM(NSInteger, SSHKitSFTPListDirFilterCode) {
    // error code from libssh
    SSHKitSFTPListDirFilterCodeAdd  = 0,
    SSHKitSFTPListDirFilterCodeIgnore,
    SSHKitSFTPListDirFilterCodeCancel,
};

typedef NS_ENUM(NSInteger, SSHKitSFTPErrorCode) {
    // error code from libssh
    SSHKitSFTPErrorCodeOK = 0,
    SSHKitSFTPErrorCodeEOF = 1,
    SSHKitSFTPErrorCodeNoSuchFile = 2,
    SSHKitSFTPErrorCodePermissionDenied = 3,
    SSHKitSFTPErrorCodeGenericFailure = 4,
    SSHKitSFTPErrorCodeBadMessage = 5,
    SSHKitSFTPErrorCodeNoConnection = 6,
    SSHKitSFTPErrorCodeConnectionLost = 7,
    SSHKitSFTPErrorCodeOpUnsupported = 8,
    SSHKitSFTPErrorCodeInvalidHandle = 9,
    SSHKitSFTPErrorCodeNoSuchPath = 10,
    SSHKitSFTPErrorCodeFileAlreadyExists = 11,
    SSHKitSFTPErrorCodeWriteProtect = 12,
    SSHKitSFTPErrorCodeNoMedia = 13,
};

typedef NS_ENUM(NSUInteger, SSHKitSFTPIsFileExist) {
    SSHKitSFTPIsFileExistNo = 0,
    SSHKitSFTPIsFileExistFile,
    SSHKitSFTPIsFileExistDirectory,
};

typedef struct sftp_attributes_struct* sshkit_sftp_attributes;

/* All implementations MUST be able to process packets with an
 * uncompressed payload length of 32768 bytes or less and a total packet
 * size of 35000 bytes or less (including 'packet_length',
 *                              'padding_length', 'payload', 'random padding', and 'mac').
 */
#define SSHKIT_CORE_SSH_MAX_PAYLOAD 16384 // 16K should appropriate for both channel and sftp

typedef NSString *(^ SSHKitAskPassBlock)(void);
typedef NSArray *(^ SSHKitAskInteractiveInfoBlock)(NSInteger, NSString *, NSString *, NSArray *);

typedef void (^ SSHKitListeningRequestCompletionBlock)(BOOL success, uint16_t boundPort, NSError *error);

// Block typedefs
typedef SSHKitSFTPListDirFilterCode(^SSHKitSFTPListDirFilter)(SSHKitSFTPFile *sftpFile);
typedef void(^SSHKitSFTPClientSuccessBlock)(void);
typedef void(^SSHKitSFTPClientFailureBlock)(NSError *error);
typedef void(^SSHKitSFTPClientProgressBlock) (unsigned long bytesNewReceived, unsigned long long bytesReceived, unsigned long long bytesTotal);
typedef void(^SSHKitSFTPClientReadFileBlock) (char *buffer, int bufferLength);

// -----------------------------------------------------------------------------
#pragma mark Advanced SSH Options
// -----------------------------------------------------------------------------

extern NSString * const kVTKitEnableCompressionKey;     // @YES or @NO
extern NSString * const kVTKitEncryptionCiphersKey;
extern NSString * const kVTKitHostKeyAlgorithmsKey;
extern NSString * const kVTKitMACAlgorithmsKey;
extern NSString * const kVTKitKeyExchangeAlgorithmsKey;
extern NSString * const kVTKitServerAliveCountMaxKey;   // <=0 will disable keepalive mech.
extern NSString * const kVTKitDebugLevelKey;

// default preferred ciphers order
extern NSString * const kVTKitDefaultEncryptionCiphers;

// default preferred host key algorithms order
extern NSString * const kVTKitDefaultHostKeyAlgorithms;

// default preferred MAC (message authentication code) algorithms
extern NSString * const kVTKitDefaultMACAlgorithms;

// default preferred key exchange algorithms order
extern NSString * const kVTKitDefaultKeyExchangeAlgorithms;

#pragma mark - Logging

/* WARN: GCD is thread-blind execution of threaded code, where you submit blocks of code to be run on any available system-owned thread.
 *
 * The drawback of this behavior is __thread keyword used by libssh DOES NOT work!
 *
 * Problem: instead of use a ssh_session struct member variable, libssh presupposes ssh_ssesion and execution thread are one-to-one map, so it uses __thread keyword to store log function and userdata for a session.
 *
 * Even worse, some libssh functions which are supposed can be run simultaneously in different threads (such as `ssh_pki_export_privkey_to_pubkey`) also print log through log callback.
 *
 * This problem leads you MUST register log callback in every possible threads to make sure logging functional, otherwise you are at risk of crash.
 *
 * This make libssh logging worthless, so actually SSHKitRegisterLogCallback is not used in SSHKitCore.
 */
typedef void (^ SSHKitLogHandler)(NSInteger priority, NSString *function, NSString *message);

/** Level
 No logging at all
    NONE 0
 
 Show only warnings
    WARN 1
 
 Get some information what's going on
    INFO 2
 
 Get detailed debuging information
    DEBUG 3
 
 Get trace output, packet information
    SSH_LOG_TRACE 4
*/
void SSHKitRegisterLogCallback(NSInteger level, SSHKitLogHandler block, dispatch_queue_t queue);
void SSHKitUnregisterLogCallback(dispatch_queue_t queue);
