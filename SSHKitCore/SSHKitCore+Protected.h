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

#define SSHKit_CHANNEL_MAX_PACKET        32768
#define SSHKit_SESSION_DEFAULT_TIMEOUT   120 // two minutes

/*
 * 1. Session Queue could not dispatch write queue sync
 */

typedef NS_ENUM(NSInteger, SSHKitChannelDataType) {
    SSHKitChannelStdoutData  = 0,
    SSHKitChannelStderrData,
};

@interface SSHKitSession ()
{
    @public
    NSMutableArray      *_forwardRequests;
}

/** Raw libssh session instance. */
@property (nonatomic, readonly) ssh_session rawSession;

@property (nonatomic, readwrite) NSMutableArray *channels;

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
}

@property (nonatomic, readwrite) SSHKitChannelType  type;
@property (nonatomic, readwrite) SSHKitChannelStage stage;

@property (readwrite) NSString      *directHost;
@property (readwrite) NSUInteger    directPort;

@property (readwrite) NSInteger forwardDestinationPort;

- (void)_doRead;
- (void)_doOpenDirect;

/**
 Create a new SSHKitChannel instance.
 
 @param session A valid, connected, SSHKitSession instance
 @returns New SSHKitChannel instance
 */
- (instancetype)initWithSession:(SSHKitSession *)session;
- (instancetype)initWithSession:(SSHKitSession *)session delegate:(id<SSHKitChannelDelegate>)aDelegate;
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

