//
//  SSHKitForwardChannel.m
//  SSHKitCore
//
//  Created by Yang Yubo on 12/6/14.
//
//

#import "SSHKitForwardChannel.h"
#import "SSHKit+Protected.h"

@implementation SSHKitForwardChannel

- (instancetype)initWithSession:(SSHKitSession *)session rawChannel:(ssh_channel)rawChannel destinationPort:(NSInteger)destinationPort
{
    if (self=[super initWithSession:session]) {
        [self.session dispatchSyncOnSessionQueue: ^{ @autoreleasepool {
            self.destinationPort = destinationPort;
            _rawChannel = rawChannel;
        }}];
        
        _state = SSHKitChannelReadWrite;
    }
    
    return self;
}

@end
