//
//  SSHKitSession+Channels.m
//  SSHKitCore
//
//  Created by Yang Yubo on 2/2/16.
//
//

#import "SSHKitSession+Channels.h"
#import "SSHKitSession.h"
#import "SSHKitCore+Protected.h"

@interface SSHKitForwardRequest : NSObject

- (instancetype)initWithListenHost:(NSString *)host port:(uint16_t)port completionHandler:(SSHKitRequestRemoteForwardCompletionBlock)completionHandler;

@property (readonly, copy) NSString    *listenHost;
@property (readonly)       uint16_t    listenPort;
@property (readonly, strong)       SSHKitRequestRemoteForwardCompletionBlock completionHandler;

@end

@implementation SSHKitSession (Channels)

#pragma mark - Creating Channels

- (SSHKitDirectChannel *)openDirectChannelWithTargetHost:(NSString *)host port:(NSUInteger)port delegate:(id<SSHKitChannelDelegate>)aDelegate {
    SSHKitDirectChannel *channel = [[SSHKitDirectChannel alloc] initWithSession:self targetHost:host targetPort:port delegate:aDelegate];
    
    __weak SSHKitSession *weakSelf = self;
    
    // We must retain channel to prevent it be released before adding to session channel container
    [self dispatchAsyncOnSessionQueue: ^{ {
        SSHKitSession *strongSelf = weakSelf;
        if (!strongSelf.isConnected) {
            [channel closeWithError:nil];
            return_from_block;
        }
        
        if ([channel doInitiateWithRawChannel:NULL]) {
            channel.stage = SSHKitChannelStageOpening;
            [channel doOpen];
        }
    }}];
    
    return channel;
}

- (SSHKitForwardChannel *)openForwardChannel {
    NSAssert([self isOnSessionQueue], @"Must be dispatched on session queue");
    
    int destination_port = 0;
    ssh_channel rawChannel = ssh_channel_accept_forward(self.rawSession, 0, &destination_port);
    
    if (!rawChannel) {
        return nil;
    }
    
    SSHKitForwardChannel *channel = [[SSHKitForwardChannel alloc] initWithSession:self destinationPort:destination_port];
    
    [channel doInitiateWithRawChannel:rawChannel];
    channel.stage = SSHKitChannelStageReady;
    
    return channel;
}

- (void)enqueueForwardRequestWithListenHost:(NSString *)host listenPort:(uint16_t)port completionHandler:(SSHKitRequestRemoteForwardCompletionBlock)completionHandler {
    __weak SSHKitSession *weakSelf = self;
    
    [self dispatchAsyncOnSessionQueue: ^{ @autoreleasepool {
        __strong SSHKitSession *strongSelf = weakSelf;
        if (!strongSelf.isConnected) {
            return_from_block;
        }
        
        SSHKitForwardRequest *request = [[SSHKitForwardRequest alloc] initWithListenHost:host port:port completionHandler:completionHandler];
        
        [strongSelf->_forwardRequests addObject:request];
        [strongSelf doSendForwardRequest];
    }}];
}

- (SSHKitShellChannel *)openSessionChannelWithTerminalType:(NSString *)type columns:(NSInteger)columns rows:(NSInteger)rows delegate:(id<SSHKitShellChannelDelegate>)aDelegate {
    SSHKitShellChannel *channel = [[SSHKitShellChannel alloc] initWithSession:self terminalType:type columns:columns rows:rows delegate:aDelegate];
    
    __weak SSHKitSession *weakSelf = self;
    
    // We must retain channel to prevent it be released before adding to session channel container
    [self dispatchAsyncOnSessionQueue: ^{ @autoreleasepool {
        __strong SSHKitSession *strongSelf = weakSelf;
        
        if (!strongSelf.isConnected) {
            [channel closeWithError:nil];
            return_from_block;
        }
        
        if ([channel doInitiateWithRawChannel:NULL]) {
            channel.stage = SSHKitChannelStageOpening;
            [channel doOpen];
        }
    }}];
    
    return channel;
}

/** !WARNING!
 tcpip-forward is session global request, requests must go one by one serially.
 Otherwise, forward request will be failed
 */
- (void)doSendForwardRequest {
    NSAssert([self isOnSessionQueue], @"Must be dispatched on session queue");
    SSHKitForwardRequest *request = _forwardRequests.firstObject;
    
    if (!request) return;
    
    int boundport = 0;
    
    int rc = ssh_channel_listen_forward(self.rawSession, request.listenHost.UTF8String, request.listenPort, &boundport);
    
    switch (rc) {
        case SSH_OK: {
            // success
            [_forwardRequests removeObject:request];
            
            // boundport may equals 0, if listenPort is NOT 0.
            boundport = boundport ? boundport : request.listenPort;
            if (request.completionHandler) request.completionHandler(YES, boundport, nil);
            
            // try next
            if (_forwardRequests.firstObject) {
                [self doSendForwardRequest];
            }
            
            break;
        }
            
        case SSH_AGAIN:
            // try next time
            break;
            
        case SSH_ERROR:
        default: {
            // failed
            [_forwardRequests removeAllObjects];
            
            if (request.completionHandler) {
                NSError *error = self.coreError;
                error = [NSError errorWithDomain:error.domain code:SSHKitErrorChannelFailure userInfo:error.userInfo];
                request.completionHandler(NO, request.listenPort, error);
            }
            
            [self disconnectIfNeeded];
            break;
        }
    }
}

@end

@interface SSHKitForwardRequest()

@property (readwrite, copy) NSString    *listenHost;
@property (readwrite)       uint16_t    listenPort;
@property (readwrite, strong)       SSHKitRequestRemoteForwardCompletionBlock completionHandler;

@end

@implementation SSHKitForwardRequest

- (instancetype)initWithListenHost:(NSString *)host port:(uint16_t)port completionHandler:(SSHKitRequestRemoteForwardCompletionBlock)completionHandler {
    self = [super init];
    
    if (self) {
        if (!host.length) {
            self.listenHost = @"localhost";
        } else {
            self.listenHost = host.lowercaseString;
        }
        
        self.listenPort = port;
        self.completionHandler = completionHandler;
    }
    
    return self;
}

- (BOOL)isEqual:(id)object {
    return [self.listenHost isEqualToString:[object listenHost]] && self.listenPort==[object listenPort];
}

@end
