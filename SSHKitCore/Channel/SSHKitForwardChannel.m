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

+ (instancetype)tryAcceptForwardChannelOnSession:(SSHKitSession *)session {
    NSAssert([session isOnSessionQueue], @"Must be dispatched on session queue");
    
    int destination_port = 0;
    ssh_channel rawChannel = ssh_channel_accept_forward(session.rawSession, 0, &destination_port);
    if (!rawChannel) {
        return nil;
    }
    
    SSHKitForwardChannel *channel = [[self alloc] initWithSession:session delegate:nil];
    
    channel->_destinationPort = destination_port;
    
    [channel _initiateWithRawChannel:rawChannel];
    
    channel.stage = SSHKitChannelStageReadWrite;
    [channel _registerCallbacks];
    
    return channel;
}

- (void)_doProcess {
    NSAssert([self.session isOnSessionQueue], @"Must be dispatched on session queue");
    
    switch (self.stage) {
        case SSHKitChannelStageReadWrite:
            [self _doWrite];
            break;
            
        case SSHKitChannelStageOpening:
        case SSHKitChannelStageClosed:
        default:
            break;
    }
}

@end
