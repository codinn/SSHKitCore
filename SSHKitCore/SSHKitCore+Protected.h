#import <CoreFoundation/CoreFoundation.h>
#import <netinet/in.h>
#import <sys/socket.h>
#import <arpa/inet.h>
#import <libssh/libssh.h>
#import "SSHKitSession.h"
#import "SSHKitChannel.h"
#import "SSHKitPrivateKeyParser.h"
#import "SSHKitHostKeyParser.h"

NSString * SSHKitGetBase64FromHostKey(ssh_key key);

#define SSHKIT_MAX_BUF_SIZE             4096    // Same size as libssh MAX_BUF_SIZE
#define SSHKIT_CHANNEL_MAX_PACKET       32768
#define SSHKIT_SESSION_DEFAULT_TIMEOUT  120     // two minutes

/*
 * 1. Session Queue could not dispatch write queue sync
 */

typedef NS_ENUM(NSInteger, SSHKitChannelDataType) {
    SSHKitChannelStdoutData  = 0,
    SSHKitChannelStderrData,
};

@interface SSHKitSession () {
    NSMutableArray      *_forwardRequests;
    NSMutableArray      *_channels;
}

/** Raw libssh session instance. */
@property (nonatomic, readonly) ssh_session rawSession;

- (BOOL)isOnSessionQueue;
- (void)disconnectIfNeeded;

@end

@interface SSHKitChannel () {
@public
    struct {
        unsigned int didReadStdoutData : 1;
        unsigned int didReadStderrData : 1;
        unsigned int didWriteData : 1;
        unsigned int didOpen : 1;
        unsigned int didCloseWithError : 1;
        unsigned int didChangePtySizeToColumnsRows : 1;
    } _delegateFlags;
}

- (BOOL)doInitiateWithRawChannel:(ssh_channel)rawChannel;

/** Raw libssh session instance. */
@property (nonatomic, readonly) ssh_channel rawChannel;

@property (nonatomic, readwrite) SSHKitChannelStage stage;

- (instancetype)initWithSession:(SSHKitSession *)session delegate:(id<SSHKitChannelDelegate>)aDelegate;

- (void)doOpen;
- (void)doWrite;
- (void)doCloseWithError:(NSError *)error;
@end


@interface SSHKitForwardChannel()

- (instancetype)initWithSession:(SSHKitSession *)session destinationPort:(NSUInteger)port;

@end

@interface SSHKitDirectChannel()

- (instancetype)initWithSession:(SSHKitSession *)session targetHost:(NSString *)host targetPort:(NSUInteger)port delegate:(id<SSHKitChannelDelegate>)aDelegate;

@end

@interface SSHKitShellChannel()

- (instancetype)initWithSession:(SSHKitSession *)session terminalType:(NSString *)type columns:(NSInteger)columns rows:(NSInteger)rows delegate:(id<SSHKitChannelDelegate>)aDelegate;

@end

@interface SSHKitPrivateKeyParser () {
    SSHKitAskPassphrasePrivateKeyBlock _passhpraseHandler;
}

@property (nonatomic, readonly) ssh_key privateKey;
@property (nonatomic, readonly) ssh_key publicKey;

@end

@interface SSHKitHostKeyParser ()

@property (nonatomic, readonly) ssh_key hostKey;

@end

