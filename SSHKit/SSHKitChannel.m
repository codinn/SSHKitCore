#import "SSHKitChannel.h"
#import "SSHKit+Protected.h"
#import <libssh/libssh.h>
#import <libssh/callbacks.h>

@interface SSHKitChannel () {
}
@end

@implementation SSHKitChannel

// -----------------------------------------------------------------------------
#pragma mark - INITIALIZER
// -----------------------------------------------------------------------------

- (instancetype)initWithSession:(SSHKitSession *)session
{
    return [self initWithSession:session delegate:nil];
}

- (instancetype)initWithSession:(SSHKitSession *)session delegate:(id<SSHKitChannelDelegate>)aDelegate
{
    if ((self = [super init])) {
        _session = session;
        // Make sure we were provided a valid session
        if (![_session isKindOfClass:[SSHKitSession class]]) {
            return nil;
        }
        
        [_session dispatchSyncOnSessionQueue: ^{ @autoreleasepool {
            _rawChannel = ssh_channel_new(_session.rawSession);
            [_session _addChannel:self];
        }}];
        
		self.delegate = aDelegate;
        
        _state = SSHKitChannelCreated;
    }

    return self;
}

- (void)dealloc
{
    [self close];
}

- (BOOL)isOpened
{
    __block BOOL flag;
    
    [self.session dispatchSyncOnSessionQueue:^ { @autoreleasepool {
        flag = _rawChannel && (ssh_channel_is_open(_rawChannel)!=0);
    }}];
    
    return flag;
}

- (void)close
{
    [self closeWithError:nil];
}

- (void)closeWithError:(NSError *) error
{
    [self.session dispatchSyncOnSessionQueue:^ { @autoreleasepool {
        if (_state == SSHKitChannelClosed) { // already closed
            return;
        }
        
        _state = SSHKitChannelClosed;
        
        // SSH_OK or SSH_ERROR, never return SSH_AGAIN
        
        // prevent server receive more then one close message
        if (self.isOpened) {
            ssh_channel_close(_rawChannel);
        }
        
        ssh_channel_free(_rawChannel);
        
        _rawChannel = NULL;
        
        if (_delegateFlags.didCloseWithError) {
            [self.delegate channelDidClose:self withError:error];
        }
        
        [self.session _removeChannel:self];
    }}];
}

#pragma mark - Properties

- (void)setDelegate:(id<SSHKitChannelDelegate>)delegate
{
	if (_delegate != delegate) {
		_delegate = delegate;
		_delegateFlags.didReadStdoutData = [delegate respondsToSelector:@selector(channel:didReadStdoutData:)];
		_delegateFlags.didReadStderrData = [delegate respondsToSelector:@selector(channel:didReadStderrData:)];
		_delegateFlags.didWriteData = [delegate respondsToSelector:@selector(channelDidWriteData:)];
        _delegateFlags.didOpen = [delegate respondsToSelector:@selector(channelDidOpen:)];
		_delegateFlags.didCloseWithError = [delegate respondsToSelector:@selector(channelDidClose:withError:)];
	}
}


#pragma mark - Others

- (void)_tryReadData:(SSHKitChannelDataType)dataType
{
    int to_read = ssh_channel_poll(_rawChannel, dataType);
    
    if (to_read==SSH_EOF) {     // eof
        [self close];
    } else if (to_read < 0) {   // error occurs, close channel
        [self closeWithError:self.session.lastError];
    } else if (to_read==0) {
        // no data
    } else {
        NSMutableData *data = [NSMutableData dataWithLength:to_read];
        ssh_channel_read(_rawChannel, data.mutableBytes, to_read, dataType);
        
        switch (dataType) {
            case SSHKitChannelStdoutData:
                if (_delegateFlags.didReadStdoutData) {
                    [self.delegate channel:self didReadStdoutData:data];
                }
                break;
            case SSHKitChannelStderrData:
                if (_delegateFlags.didReadStderrData) {
                    [self.delegate channel:self didReadStderrData:data];
                }
                break;
            default:
                break;
        }
    }
}

/**
 * Reads the first available bytes that become available on the channel.
 **/
- (void)_doRead
{
    switch (_state) {
        case SSHKitChannelClosed:
            break;
        
        case SSHKitChannelOpening:
            [self _doOpen];
            break;
            
        case SSHKitChannelReadWrite:
            [self _tryReadData:SSHKitChannelStdoutData];
            [self _tryReadData:SSHKitChannelStderrData];
            
        default:
            break;
    }
}

- (void)writeData:(NSData *)data
{
    __weak SSHKitChannel *weakSelf = self;
    
    [self.session dispatchAsyncOnSessionQueue:^{ @autoreleasepool {
        if (_state != SSHKitChannelReadWrite) {
            return_from_block;
        }
        
        __strong SSHKitChannel *strongSelf = weakSelf;
        
        uint32_t wrote = 0;
        
        do {
            ssize_t i = ssh_channel_write(_rawChannel, &[data bytes][wrote], (uint32_t)data.length-wrote);
            
            if (i < 0) {
                [strongSelf closeWithError:strongSelf.session.lastError];
                return;
            }
            
            wrote += i;
        } while (wrote < data.length && _rawChannel);
        
        if (_delegateFlags.didWriteData) {
            [strongSelf.delegate channelDidWriteData:strongSelf];
        }
    }}];
}

- (void)_doOpen
{
    @throw [NSException exceptionWithName:NSInvalidArgumentException reason:[NSString stringWithFormat:@"%s must be overridden in a subclass/category", __PRETTY_FUNCTION__] userInfo:nil];
}

@end
