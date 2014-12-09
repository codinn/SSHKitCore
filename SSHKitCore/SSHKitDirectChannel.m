//
//  SSHKitDirectChannel.m
//  SSHKit
//
//  Created by Brant Young on 10/29/14.
//
//

#import "SSHKitDirectChannel.h"
#import "SSHKit+Protected.h"

@implementation SSHKitDirectChannel

- (instancetype)initWithSession:(SSHKitSession *)session delegate:(id<SSHKitChannelDelegate>)aDelegate
{
    if ((self = [super initWithSession:session delegate:aDelegate])) {
        [self.session dispatchSyncOnSessionQueue: ^{ @autoreleasepool {
            _rawChannel = ssh_channel_new(self.session.rawSession);
            [self.session _addChannel:self];
        }}];
    }
    
    return self;
}

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
