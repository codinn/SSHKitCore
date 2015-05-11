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

#define SSHKit_MAX_BUF_SIZE             4096    // Same size as libssh MAX_BUF_SIZE
#define SSHKit_CHANNEL_MAX_PACKET       32768
#define SSHKit_SESSION_DEFAULT_TIMEOUT  120     // two minutes

/*
 * 1. Session Queue could not dispatch write queue sync
 */

typedef NS_ENUM(NSInteger, SSHKitChannelDataType) {
    SSHKitChannelStdoutData  = 0,
    SSHKitChannelStderrData,
};

@interface SSHKitForwardRequest : NSObject

- (instancetype)initWithListenHost:(NSString *)host port:(uint16_t)port completionHandler:(SSHKitRequestRemoteForwardCompletionBlock)completionHandler;

@property (readonly, copy) NSString    *listenHost;
@property (readonly)       uint16_t    listenPort;
@property (readonly, strong)       SSHKitRequestRemoteForwardCompletionBlock completionHandler;

@end

@interface SSHKitSession ()

/** Raw libssh session instance. */
@property (nonatomic, readonly) ssh_session rawSession;

- (void)addChannel:(SSHKitChannel *)channel;
- (void)removeChannel:(SSHKitChannel *)channel;

- (SSHKitForwardRequest *)firstForwardRequest;
- (void)addForwardRequest:(SSHKitForwardRequest *)request;
- (void)removeForwardRequest:(SSHKitForwardRequest *)request;
- (void)removeAllForwardRequest;

- (BOOL)isOnSessionQueue;

@end

@interface SSHKitChannel ()

/** Raw libssh session instance. */
@property (nonatomic, readonly) ssh_channel rawChannel;

+ (instancetype)_tryCreateForwardChannelFromSession:(SSHKitSession *)session;
+ (void)_doRequestRemoteForwardOnSession:(SSHKitSession *)session;

- (void)_doProcess;

- (void)_tryToWrite;

- (void)_doOpenSession;
- (void)_doRequestPty;
- (void)_doRequestShell;

- (void)_doOpenDirect;
@end

@interface SSHKitPrivateKeyParser ()
{
    SSHKitAskPassphrasePrivateKeyBlock _passhpraseHandler;
}

@property (nonatomic, readonly) ssh_key privateKey;
@property (nonatomic, readonly) ssh_key publicKey;

@end

@interface SSHKitHostKeyParser ()

@property (nonatomic, readonly) ssh_key hostKey;

@end

