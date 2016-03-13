//
//  SSHKitDirectChannel.m
//  SSHKitCore
//
//  Created by Yang Yubo on 2/2/16.
//
//

#import "SSHKitDirectChannel.h"
#import "SSHKitSession.h"
#import "SSHKitCore+Protected.h"

@implementation SSHKitDirectChannel

- (instancetype)initWithSession:(SSHKitSession *)session targetHost:(NSString *)host targetPort:(NSUInteger)port delegate:(id<SSHKitChannelDelegate>)aDelegate {
    if (self = [super initWithSession:session delegate:aDelegate]) {
        _targetHost = host;
        _targetPort = port;
    }
    
    return self;
}

- (void)doOpen {
    NSAssert([self.session isOnSessionQueue], @"Must be dispatched on session queue");
    
    int result = ssh_channel_open_forward(self.rawChannel, self.targetHost.UTF8String, (int)self.targetPort, "127.0.0.1", 22);
    
    switch (result) {
        case SSH_AGAIN:
            // try again
            break;
            
        case SSH_OK:
            self.stage = SSHKitChannelStageReady;
            // opened
            if (_delegateFlags.didOpen) {
                [self.delegate channelDidOpen:self];
            }
            break;
        default: {
            // open failed
            NSError *error = [NSError errorWithDomain:SSHKitCoreErrorDomain
                                                 code:SSHKitErrorConnectFailure
                                             userInfo:@{ NSLocalizedDescriptionKey : @"Open Direct Failed" }];
            if (self.session.coreError) {
                error = self.session.coreError;
            }
            [self doCloseWithError:error];
            [self.session disconnectIfNeeded];
            break;
        }
    }
}

@end
