#import <CoreFoundation/CoreFoundation.h>
#import <netinet/in.h>
#import <sys/socket.h>
#import <arpa/inet.h>
#import <libssh/libssh.h>
#import "SSHKitSession.h"
#import "SSHKitChannel.h"
#import "SSHKitIdentityParser.h"

NSString * SSHKitGetBase64FromHostKey(ssh_key key);

#define SSHKit_CHANNEL_MAX_PACKET        32768
#define SSHKit_SESSION_DEFAULT_TIMEOUT   120 // two minutes
#define SSHKit_SESSION_MIN_TIMEOUT       5

/*
 * 1. Session Queue could not dispatch write queue sync
 */

typedef NS_ENUM(NSInteger, SSHKitChannelState) {
    SSHKitChannelInvalid,        // channel has not been inited correctly
    SSHKitChannelCreated,        // channel has been created
    SSHKitChannelOpening,        // the channel is opening
    SSHKitChannelReadWrite,      // the channel has been opened, we can read / write from the channel
    SSHKitChannelClosed,         // the channel has been closed
};

typedef NS_ENUM(NSInteger, SSHKitChannelDataType) {
    SSHKitChannelStdoutData  = 0,
    SSHKitChannelStderrData,
};

@interface SSHKitSession ()

/** Raw libssh session instance. */
@property (nonatomic, readonly) ssh_session rawSession;

/** Raw session socket. */
@property (nonatomic, readonly) socket_t socketFD;

- (void)_addChannel:(SSHKitChannel *)channel;
- (void)_removeChannel:(SSHKitChannel *)channel;

@end

@interface SSHKitChannel () {
    @protected
    struct {
        unsigned int didReadStdoutData : 1;
        unsigned int didReadStderrData : 1;
        unsigned int didWriteData : 1;
        unsigned int didOpen : 1;
        unsigned int didCloseWithError : 1;
    } _delegateFlags;
    
    ssh_channel _rawChannel;
    SSHKitChannelState _state;
}

@property (readwrite) SSHKitChannelType type;

- (void)_doRead;
- (void)_doOpen;

/**
 Create a new SSHKitChannel instance.
 
 @param session A valid, connected, SSHKitSession instance
 @returns New SSHKitChannel instance
 */
- (instancetype)initWithSession:(SSHKitSession *)session;
- (instancetype)initWithSession:(SSHKitSession *)session delegate:(id<SSHKitChannelDelegate>)aDelegate;
@end

@interface SSHKitDirectChannel ()

- (void)_openWithHost:(NSString *)host onPort:(uint16_t)port;

@end

@interface SSHKitForwardChannel ()
- (instancetype)initWithSession:(SSHKitSession *)session rawChannel:(ssh_channel)rawChannel destinationPort:(NSInteger)destinationPort;

@property (readwrite) NSInteger destinationPort;
@end

@interface SSHKitIdentityParser ()
{
    SSHKitAskPassphrasePrivateKeyBlock _passhpraseHandler;
    NSString *_keyPath;
}

@property (nonatomic, readonly) ssh_key privateKey;
@property (nonatomic, readonly) ssh_key publicKey;

@end
