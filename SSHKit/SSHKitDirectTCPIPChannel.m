//
//  SSHKitDirectTCPIPChannel.m
//  SSHKit
//
//  Created by Brant Young on 10/29/14.
//
//

#import "SSHKitDirectTCPIPChannel.h"
#import "SSHKit+Protected.h"

@implementation SSHKitDirectTCPIPChannel

- (void)_doOpen
{
    if (_state == SSHKitChannelClosed) {
        return;
    }
    
    int result = ssh_channel_open_forward(_rawChannel, self.host.UTF8String, (int)self.port, "127.0.0.1", 22);
        
    switch (result) {
        case SSH_AGAIN:
            _state = SSHKitChannelOpening;
            break;
        case SSH_OK:
            _state = SSHKitChannelReadWrite;
            
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

- (void)_openWithHost:(NSString *)host onPort:(uint16_t)port
{
    self.host = host;
    self.port = port;
    self.type = SSHKitChannelTypeDirect;
    
    [self.session dispatchAsyncOnSessionQueue: ^ { @autoreleasepool {
        [self _doOpen];
    }}];
}

@end
