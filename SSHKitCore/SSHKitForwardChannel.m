//
//  SSHKitForwardChannel.m
//  SSHKitCore
//
//  Created by Yang Yubo on 12/6/14.
//
//

#import "SSHKitForwardChannel.h"
#import "SSHKitCore+Protected.h"

@implementation SSHKitForwardChannel

- (instancetype)initWithSession:(SSHKitSession *)session rawChannel:(ssh_channel)rawChannel destinationPort:(NSInteger)destinationPort
{
    if (self=[super initWithSession:session]) {
        __weak SSHKitForwardChannel *weakSelf = self;
        
        [self.session dispatchSyncOnSessionQueue: ^{ @autoreleasepool {
            __strong SSHKitForwardChannel *strongSelf = weakSelf;
            
            self.destinationPort = destinationPort;
            strongSelf->_rawChannel = rawChannel;
        }}];
        
        self.stage = SSHKitChannelStageReadWrite;
    }
    
    return self;
}

+ (instancetype)tryAcceptForwardChannelOnSession:(SSHKitSession *)session
{
    int destination_port = 0;
    ssh_channel channel = ssh_channel_accept_forward(session.rawSession, 0, &destination_port);
    
    if (!channel) {
        return nil;
    }
    
    return[[SSHKitForwardChannel alloc] initWithSession:session rawChannel:channel destinationPort:destination_port];
}

@end

@implementation SSHKitRemoteForwardRequest

- (instancetype)initWithSession:(SSHKitSession *)session listenHost:(NSString *)host onPort:(uint16_t)port completionHandler:(SSHKitRequestRemoteForwardCompletionBlock)completionHandler
{
    if (self=[super init]) {
        self.session = session;
        self.listenHost = host;
        self.listenPort = port;
        self.completionHandler = completionHandler;
    }
    
    return self;
}

- (int)request
{
    int boundport = 0;
    int rc = ssh_forward_listen(self.session.rawSession, self.listenHost.UTF8String, self.listenPort, &boundport);
    
    switch (rc) {
        case SSH_OK:
        {
            // success
            [[NSNotificationCenter defaultCenter] postNotificationName:SSHKIT_REMOTE_FORWARD_COMPLETE_NOTIFICATION
                                                                object:self
                                                              userInfo:nil];
            
            // boundport may equals 0, if listenPort is NOT 0.
            boundport = boundport ? boundport : self.listenPort;
            self.completionHandler(YES, boundport, nil);
            break;
        }
            
        case SSH_AGAIN:
            // try again
            break;
            
        case SSH_ERROR:
        default:
        {
            // failed
            [[NSNotificationCenter defaultCenter] postNotificationName:SSHKIT_REMOTE_FORWARD_COMPLETE_NOTIFICATION
                                                                object:self
                                                              userInfo:nil];
            self.completionHandler(NO, self.listenPort, self.session.lastError);
            break;
        }
    }
    
    return rc;
}

@end
