//
//  SSHKitForwardChannel.m
//  SSHKitCore
//
//  Created by Yang Yubo on 2/2/16.
//
//

#import "SSHKitForwardChannel.h"
#import "SSHKitSession.h"
#import "SSHKitCore+Protected.h"

@implementation SSHKitForwardChannel

- (instancetype)initWithSession:(SSHKitSession *)session destinationPort:(NSUInteger)port {
    if (self = [super initWithSession:session delegate:nil]) {
        _destinationPort = port;
    }
    
    return self;
}

- (void)doProcess {
    NSAssert([self.session isOnSessionQueue], @"Must be dispatched on session queue");
    
    switch (self.stage) {
        case SSHKitChannelStageReadWrite:
            [self doWrite];
            break;
            
        case SSHKitChannelStageOpening:
        case SSHKitChannelStageClosed:
        default:
            break;
    }
}

@end
