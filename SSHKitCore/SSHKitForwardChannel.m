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
        __weak SSHKitForwardChannel *weakSelf = self;
        
        [self.session dispatchSyncOnSessionQueue: ^{ @autoreleasepool {
            __strong SSHKitForwardChannel *strongSelf = weakSelf;
            
            self.destinationPort = destinationPort;
            strongSelf->_rawChannel = rawChannel;
        }}];
        
        _state = SSHKitChannelStageReadWrite;
    }
    
    return self;
}

@end
