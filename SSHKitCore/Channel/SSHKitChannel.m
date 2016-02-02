#import "SSHKitChannel.h"
#import "SSHKitCore+Protected.h"
#import <libssh/libssh.h>
#import <libssh/callbacks.h>

typedef struct ssh_channel_callbacks_struct channel_callbacks;
static channel_callbacks s_null_channel_callbacks = {0};

@interface SSHKitChannel () {
    channel_callbacks   _callback;
}

@end

@implementation SSHKitChannel

// -----------------------------------------------------------------------------
#pragma mark - Initializer
// -----------------------------------------------------------------------------

/**
 Create a new SSHKitChannel instance.
 
 @param session A valid, connected, SSHKitSession instance
 @returns New SSHKitChannel instance
 */

- (instancetype)initWithSession:(SSHKitSession *)session delegate:(id<SSHKitChannelDelegate>)aDelegate {
    if ((self = [super init])) {
        _session = session;
		self.delegate = aDelegate;
        self.stage = SSHKitChannelStageInvalid;
    }

    return self;
}

- (BOOL)isOpened {
    __block BOOL flag = NO;
    
    __weak SSHKitChannel *weakSelf = self;
    [self.session dispatchSyncOnSessionQueue:^ { @autoreleasepool {
        __strong SSHKitChannel *strongSelf = weakSelf;
        
        flag = strongSelf->_rawChannel && (ssh_channel_is_open(strongSelf->_rawChannel)!=0);
    }}];
    
    return flag;
}

#pragma mark - Close Channel

- (void)close
{
    [self closeWithError:nil];
}

- (void)closeWithError:(NSError *)error
{
    __weak SSHKitChannel *weakSelf = self;
    [self.session dispatchAsyncOnSessionQueue:^ { @autoreleasepool {
        __strong SSHKitChannel *strongSelf = weakSelf;
        if (!strongSelf) {
            return_from_block;
        }
        
        [strongSelf _doCloseWithError:error];
    }}];
}

- (void)_doCloseWithError:(NSError *)error {
    NSAssert([self.session isOnSessionQueue], @"Must be dispatched on session queue");

    if (self.stage == SSHKitChannelStageClosed) { // already closed
        return;
    }
    
    self.stage = SSHKitChannelStageClosed;
    
    if (error) {
        self.session.logWarn(error.localizedDescription);
    }
    
    // prevent server receive more then one close message
    if (ssh_channel_is_open(_rawChannel)) {
        ssh_channel_send_eof(_rawChannel);
        ssh_channel_close(_rawChannel);
    }
    
    /** When we free a channel, raw channel itself actually might retained
     * in session channel list, it doesn't acually be "freed", it might wating for
     * remote closed message.
     * So we need to set callback here to a static value to avoid BAD MEM ACCESS
     */
    [self _unregesterCallbacks];
    
    ssh_channel_free(self->_rawChannel);
    self->_rawChannel = NULL;
    
    if (_delegateFlags.didCloseWithError) {
        [self.delegate channelDidClose:self withError:error];
    }
    
    [self.session removeChannel:self];
}

#pragma mark - Read / Write

- (void)_doProcess {
    @throw [NSException exceptionWithName:NSInternalInconsistencyException
                                   reason:[NSString stringWithFormat:@"You must override %@ in a subclass", NSStringFromSelector(_cmd)]
                                 userInfo:nil];
}

/**
 * Reads the first available bytes that become available on the channel.
 **/
static int channel_data_available(ssh_session session,
                                  ssh_channel channel,
                                  void *data,
                                  uint32_t len,
                                  int is_stderr,
                                  void *userdata)
{
    SSHKitChannel *selfChannel = (__bridge SSHKitChannel *)userdata;
    NSData *readData = [NSData dataWithBytes:data length:len];
    
    if (is_stderr) {
        if (selfChannel->_delegateFlags.didReadStderrData) {
            [selfChannel.delegate channel:selfChannel didReadStderrData:readData];
        }
    } else {
        if (selfChannel->_delegateFlags.didReadStdoutData) {
            [selfChannel.delegate channel:selfChannel didReadStdoutData:readData];
        }
    }
    
    return len;
}

static void channel_close_received(ssh_session session,
                                   ssh_channel channel,
                                   void *userdata)
{
    SSHKitChannel *selfChannel = (__bridge SSHKitChannel *)userdata;
    [selfChannel _doCloseWithError:nil];
}

static void channel_eof_received(ssh_session session,
                                 ssh_channel channel,
                                 void *userdata)
{
    SSHKitChannel *selfChannel = (__bridge SSHKitChannel *)userdata;
    [selfChannel _doCloseWithError:nil];
}

- (void)writeData:(NSData *)data {
    if (!data.length) {
        return;
    }
    
    __weak SSHKitChannel *weakSelf = self;
    
    [self.session dispatchAsyncOnSessionQueue:^{ @autoreleasepool {
        __strong SSHKitChannel *strongSelf = weakSelf;
        
        if (strongSelf.stage != SSHKitChannelStageReadWrite || !strongSelf.session.isConnected) {
            return_from_block;
        }
        
        strongSelf->_pendingWriteData = data;
        
        // resume session write dispatch source
        [strongSelf _doWrite];
    }}];
}

NS_INLINE BOOL is_channel_writable(ssh_channel raw_channel) {
    return raw_channel && (ssh_channel_window_size(raw_channel) > 0);
}

- (void)_doWrite {
    NSAssert([self.session isOnSessionQueue], @"Must be dispatched on session queue");
    
    if ( !_pendingWriteData.length || !is_channel_writable(_rawChannel) ) {
        return;
    }
    
    uint32_t datalen = (uint32_t)_pendingWriteData.length;
    
    int wrote = ssh_channel_write(_rawChannel, _pendingWriteData.bytes, datalen);
    
    if ( (wrote < 0) || (wrote>datalen) ) {
        [self _doCloseWithError:self.session.coreError];
        [self.session disconnectIfNeeded];
        return;
    }
    
    if (wrote==0) {
        return;
    }
    
    if (wrote!=datalen) {
        // libssh resize remote window, it's equivalent to E_AGAIN
        _pendingWriteData = [_pendingWriteData subdataWithRange:NSMakeRange(wrote, datalen-wrote)];
        return;
    }
    
    // all data wrote
    _pendingWriteData = nil;
    
    if (_delegateFlags.didWriteData) {
        [self.delegate channelDidWriteData:self];
    }
}

#pragma mark - Internal Utils

- (void)_registerCallbacks {
    _callback = (channel_callbacks) {
        .userdata               = (__bridge void *)(self),
        .channel_data_function  = channel_data_available,
        .channel_close_function = channel_close_received,
        .channel_eof_function   = channel_eof_received,
    };
    
    ssh_callbacks_init(&_callback);
    ssh_set_channel_callbacks(_rawChannel, &_callback);
}

- (void)_unregesterCallbacks {
    ssh_callbacks_init(&s_null_channel_callbacks);
    ssh_set_channel_callbacks(self->_rawChannel, &s_null_channel_callbacks);
}

- (BOOL)_initiate {
    NSAssert([self.session isOnSessionQueue], @"Must be dispatched on session queue");
    
    _rawChannel = ssh_channel_new(self.session.rawSession);
    
    if (!_rawChannel) return NO;
    
    // add channel to session list
    [self.session addChannel:self];
    
    self.stage = SSHKitChannelStageOpening;
    
    return YES;
}

- (BOOL)_initiateWithRawChannel:(ssh_channel)rawChannel {
    NSAssert([self.session isOnSessionQueue], @"Must be dispatched on session queue");
    
    _rawChannel = rawChannel;
    
    // add channel to session list
    [self.session addChannel:self];
    
    self.stage = SSHKitChannelStageOpening;
    
    return YES;
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
        _delegateFlags.didChangePtySizeToColumnsRows = [delegate respondsToSelector:@selector(channel:didChangePtySizeToColumns:rows:withError:)];
    }
}

@end
