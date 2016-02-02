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

- (void)openWithTargetHost:(NSString *)host port:(NSUInteger)port {
    self.stage = SSHKitChannelStageWating;
    _targetHost = host;
    _targetPort = port;
    
    __weak SSHKitDirectChannel *weakSelf = self;
    [self.session dispatchAsyncOnSessionQueue: ^{ @autoreleasepool {
        __strong SSHKitDirectChannel *strongSelf = weakSelf;
        
        if (!strongSelf) return;
        
        if (!strongSelf.session.isConnected || strongSelf.stage != SSHKitChannelStageWating) {
            if (strongSelf->_delegateFlags.didCloseWithError) {
                [strongSelf.delegate channelDidClose:strongSelf withError:nil];
            }
            
            return_from_block;
        }
        
        if ([strongSelf _initiate]) {
            [strongSelf _openDirect];
        }
    }}];
}

- (void)_openDirect {
    NSAssert([self.session isOnSessionQueue], @"Must be dispatched on session queue");
    
    int result = ssh_channel_open_forward(self.rawChannel, self.targetHost.UTF8String, (int)self.targetPort, "127.0.0.1", 22);
    
    switch (result) {
        case SSH_AGAIN:
            // try again
            break;
            
        case SSH_OK:
            self.stage = SSHKitChannelStageReadWrite;
            [self _registerCallbacks];
            // opened
            if (_delegateFlags.didOpen) {
                [self.delegate channelDidOpen:self];
            }
            break;
        default: {
            // open failed
            // [self _doCloseWithError:self.session.lastError];
            NSError *error = [NSError errorWithDomain:SSHKitCoreErrorDomain
                                                 code:SSHKitErrorConnectFailure
                                             userInfo:@{ NSLocalizedDescriptionKey : @"Open Direct Failed" }];
            if (self.session.coreError) {
                error = self.session.coreError;
            }
            [self _doCloseWithError:error];  // self.session.lastError
            [self.session disconnectIfNeeded];
            break;
        }
    }
}

- (void)_doProcess {
    NSAssert([self.session isOnSessionQueue], @"Must be dispatched on session queue");
    
    switch (self.stage) {
        case SSHKitChannelStageOpening:
            [self _openDirect];
            
            break;
            
        case SSHKitChannelStageReadWrite:
            [self _doWrite];
            break;
            
        case SSHKitChannelStageClosed:
        default:
            break;
    }
}

@end
