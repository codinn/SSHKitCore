//
//  SSHKitShellChannel.m
//  SSHKitCore
//
//  Created by Yang Yubo on 2/2/16.
//
//

#import "SSHKitShellChannel.h"
#import "SSHKitSession.h"
#import "SSHKitCore+Protected.h"

typedef NS_ENUM(NSUInteger, SessionChannelReqState) {
    SessionChannelReqNone = 0,  // session channel has not been opened yet
    SessionChannelReqPty,       // is requesting a pty
    SessionChannelReqShell,     // is requesting a shell
};

@interface SSHKitShellChannel ()

@property (nonatomic, weak) id<SSHKitShellChannelDelegate> delegate;

@property (nonatomic) SessionChannelReqState   reqState;

@end

@implementation SSHKitShellChannel

@dynamic delegate;

- (instancetype)initWithSession:(SSHKitSession *)session terminalType:(NSString *)type columns:(NSInteger)columns rows:(NSInteger)rows delegate:(id<SSHKitChannelDelegate>)aDelegate {
    if (self=[super initWithSession:session delegate:aDelegate]) {
        _terminalType = type;
        _columns = columns;
        _rows = rows;
        _reqState = SessionChannelReqNone;
    }
    
    return self;
}

- (void)doOpen {
    switch (self.reqState) {
        case SessionChannelReqNone:
            // 1. open session channel
            [self _openSession];
            break;
            
        case SessionChannelReqPty:
            // 2. request pty
            [self _requestPty];
            break;
            
        case SessionChannelReqShell:
            // 2. request shell
            [self _requestShell];
            break;
    }
}

- (void)_openSession {
    int result = ssh_channel_open_session(self.rawChannel);
    
    switch (result) {
        case SSH_AGAIN:
            // try next time
            break;;
            
        case SSH_OK:
            // succeed, requests a pty
            self.reqState = SessionChannelReqPty;
            [self _requestPty];
            break;
            
        default:
            // open failed
            [self doCloseWithError:self.session.coreError];
            [self.session disconnectIfNeeded];
            break;
    }
}

- (void)_requestPty {
    int result = ssh_channel_request_pty_size(self.rawChannel, _terminalType.UTF8String, (int)_columns, (int)_rows);
    
    switch (result) {
        case SSH_AGAIN:
            // try next time
            break;
            
        case SSH_OK:
            // succeed, requests a pty
            self.reqState = SessionChannelReqShell;
            [self _requestShell];
            
            break;
            
        default:
            // open failed
            [self doCloseWithError:self.session.coreError];
            [self.session disconnectIfNeeded];
            break;
    }
}

- (void)_requestShell {
    int result = ssh_channel_request_shell(self.rawChannel);
    
    switch (result) {
        case SSH_AGAIN:
            // try next time
            break;
            
        case SSH_OK:
            self.reqState = SessionChannelReqNone;
            // succeed, mark channel ready
            self.stage = SSHKitChannelStageReady;
            if (_delegateFlags.didOpen) {
                [self.delegate channelDidOpen:self];
            }
            break;
            
        default:
            // open failed
            [self doCloseWithError:self.session.coreError];
            [self.session disconnectIfNeeded];
            break;
    }
}

- (void)changePtySizeToColumns:(NSInteger)columns rows:(NSInteger)rows {
    __weak SSHKitShellChannel *weakSelf = self;
    
    [self.session dispatchAsyncOnSessionQueue:^{ @autoreleasepool {
        __strong SSHKitShellChannel *strongSelf = weakSelf;
        
        if (strongSelf.stage != SSHKitChannelStageReady || !strongSelf.session.isConnected) {
            return_from_block;
        }
        
        int rc = ssh_channel_change_pty_size(strongSelf.rawChannel, (int)columns, (int)rows);
        
        if (!strongSelf->_delegateFlags.didChangePtySizeToColumnsRows) {
            return;
        }
        
        NSError *error = nil;
        
        // According to "6.7.  Window Dimension Change Message", "window-change" request won't receive a response, `ssh_channel_change_pty_size` will never return SSH_AGAIN
        if (rc != SSH_OK) {
            error = strongSelf.session.coreError;
            if (!error) {
                error = [NSError errorWithDomain:SSHKitLibsshErrorDomain
                                            code:rc
                                        userInfo: @{ NSLocalizedDescriptionKey : @"Failed to change remote pty size" }];
            }
        }
        
        [strongSelf.delegate channel:strongSelf didChangePtySizeToColumns:columns rows:rows withError:error];
    }}];
}

@end
