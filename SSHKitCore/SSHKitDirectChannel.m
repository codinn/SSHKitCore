//
//  SSHKitDirectChannel.m
//  SSHKit
//
//  Created by Yang Yubo on 10/29/14.
//
//

#import "SSHKitDirectChannel.h"
#import "SSHKitCore+Protected.h"

@implementation SSHKitDirectChannel

- (instancetype)initWithSession:(SSHKitSession *)session delegate:(id<SSHKitChannelDelegate>)aDelegate
{
    if ((self = [super initWithSession:session delegate:aDelegate])) {
        __weak SSHKitDirectChannel *weakSelf = self;
        
        [self.session dispatchSyncOnSessionQueue: ^{ @autoreleasepool {
            __strong SSHKitDirectChannel *strongSelf = weakSelf;
            
            if (!strongSelf) {
                return;
            }
            
            strongSelf->_rawChannel = ssh_channel_new(strongSelf.session.rawSession);
        }}];
    }
    
    return self;
}

- (void)_doOpen
{
    self.stage = SSHKitChannelStageOpening;
    
    int result = ssh_channel_open_forward(_rawChannel, self.host.UTF8String, (int)self.port, "127.0.0.1", 22);
        
    switch (result) {
        case SSH_AGAIN:
            // try again
            break;
            
        case SSH_OK:
            self.stage = SSHKitChannelStageReadWrite;
            
            // opened
            
            if (_delegateFlags.didOpen) {
                [self.delegate channelDidOpen:self];
            }
            break;
            
        default:
            // open failed
            [self closeWithError:self.session.lastError];
            break;
    }
}

- (void)setPeerHost:(NSString *)host port:(NSUInteger)port
{
    self.host = host;
    self.port = port;
}

@end
