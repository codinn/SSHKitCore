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
#include <termios.h>

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
            [self doCloseWithError:self.session.libsshError];
            [self.session disconnectIfNeeded];
            break;
    }
}

- (struct termios)termio_build_termdata:(BOOL) isUTF8 {
    struct termios term = { 0 };
    
    // UTF-8 input will be added on demand.
    term.c_iflag = TTYDEF_IFLAG | (isUTF8 ? IUTF8 : 0);
    term.c_oflag = TTYDEF_OFLAG;
    term.c_cflag = TTYDEF_CFLAG;
    term.c_lflag = TTYDEF_LFLAG;
    
    term.c_cc[VEOF]    = CEOF;
    term.c_cc[VEOL]    = CEOL;
    term.c_cc[VEOL2]   = CEOL;
    term.c_cc[VERASE]  = CERASE;           // DEL
    term.c_cc[VWERASE] = CWERASE;
    term.c_cc[VKILL]   = CKILL;
    term.c_cc[VREPRINT] = CREPRINT;
    term.c_cc[VINTR]   = CINTR;
    term.c_cc[VQUIT]   = CQUIT;           // Control+backslash
    term.c_cc[VSUSP]   = CSUSP;
    term.c_cc[VDSUSP]  = CDSUSP;
    term.c_cc[VSTART]  = CSTART;
    term.c_cc[VSTOP]   = CSTOP;
    term.c_cc[VLNEXT]  = CLNEXT;
    term.c_cc[VDISCARD] = CDISCARD;
    term.c_cc[VMIN]    = CMIN;
    term.c_cc[VTIME]   = CTIME;
    term.c_cc[VSTATUS] = CSTATUS;
    
    term.c_ispeed = B38400;
    term.c_ospeed = B38400;
    
    return term;
}

- (void)_requestPty {
    struct termios tios = [self termio_build_termdata:YES];
    int result = ssh_channel_request_pty_size_modes(self.rawChannel, _terminalType.UTF8String, (int)_columns, (int)_rows, &tios);
  
    
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
            [self doCloseWithError:self.session.libsshError];
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
            [self doCloseWithError:self.session.libsshError];
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
            error = strongSelf.session.libsshError;
            if (!error) {
                error = [NSError errorWithDomain:SSHKitLibsshErrorDomain
                                            code:rc
                                        userInfo: @{ NSLocalizedDescriptionKey : @"Failed to change remote pty size" }];
            }
        } else {
            strongSelf->_columns = columns;
            strongSelf->_rows = rows;
        }
        
        [strongSelf.delegate channel:strongSelf didChangePtySizeToColumns:columns rows:rows withError:error];
    }}];
}

@end
