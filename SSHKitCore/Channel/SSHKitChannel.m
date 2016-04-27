#import "SSHKitChannel.h"
#import "SSHKitCore+Protected.h"
#import <libssh/libssh.h>
#import <libssh/callbacks.h>

typedef struct ssh_channel_callbacks_struct channel_callbacks;
static channel_callbacks s_null_channel_callbacks = {0};

@interface SSHKitChannel () {
    channel_callbacks   _callback;
    NSData              *_pendingWriteData;
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
        self.stage = SSHKitChannelStageInitial;
    }

    return self;
}

#pragma mark - Close Channel

- (void)close {
    __weak SSHKitChannel *weakSelf = self;
    [self.session dispatchAsyncOnSessionQueue:^ {
        __strong SSHKitChannel *strongSelf = weakSelf;
        if (!strongSelf) {
            return_from_block;
        }
        
        [strongSelf doCloseWithError:nil];
    }];
}

- (void)doCloseWithError:(NSError *)error {
    NSAssert([self.session isOnSessionQueue], @"Must be dispatched on session queue");

    if (self.stage == SSHKitChannelStageClosed) { // already closed
        return;
    }
    
    self.stage = SSHKitChannelStageClosed;
    
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
    if (self.rawSFTPSession) {
        sftp_free(self.rawSFTPSession);
        _rawSFTPSession = NULL;
    }
    self->_rawChannel = NULL;
    
    if (_delegateFlags.didCloseWithError) {
        [self.delegate channelDidClose:self withError:error];
    }
}

#pragma mark - Read / Write

- (void)doOpen {
    @throw [NSException exceptionWithName:NSInternalInconsistencyException
                                   reason:[NSString stringWithFormat:@"You must override %@ in a subclass", NSStringFromSelector(_cmd)]
                                 userInfo:nil];
}

- (int)_didReceiveData:(NSData *)readData isSTDError:(BOOL)isSTDError {
    if (isSTDError) {
        if (self->_delegateFlags.didReadStderrData) {
            [self.delegate channel:self didReadStderrData:readData];
        }
    } else {
        if (self->_delegateFlags.didReadStdoutData) {
            [self.delegate channel:self didReadStdoutData:readData];
        }
    }
    return (int)readData.length;
}

- (void)writeData:(NSData *)data {
    if (!data.length) {
        return;
    }
    
    __weak SSHKitChannel *weakSelf = self;
    
    [self.session dispatchAsyncOnSessionQueue:^{ @autoreleasepool {
        __strong SSHKitChannel *strongSelf = weakSelf;
        
        if (!strongSelf || strongSelf.stage != SSHKitChannelStageReady || !strongSelf.session.isConnected) {
            // push data and wait for channel prepared
            return_from_block;
        }
        
        strongSelf->_pendingWriteData = data;
        
        // do write if channel was opened
        [strongSelf doWrite];
    }}];
}

NS_INLINE BOOL is_channel_writable(ssh_channel raw_channel) {
    return raw_channel && (ssh_channel_window_size(raw_channel) > 0);
}

- (void)doWrite {
    NSAssert([self.session isOnSessionQueue], @"Must be dispatched on session queue");
    
    if ( !_pendingWriteData.length || !is_channel_writable(_rawChannel) ) {
        return;
    }
    
    uint32_t datalen = (uint32_t)_pendingWriteData.length;
    
    int wrote = ssh_channel_write(_rawChannel, _pendingWriteData.bytes, datalen);
    
    if ( (wrote < 0) || (wrote>datalen) ) {
        [self doCloseWithError:self.session.libsshError];
        [self.session disconnectIfNeeded];
        return;
    }
    
    if (wrote==0) {
        return;
    }
    
    if (wrote!=datalen) {
        // libssh will resize remote window, it's equivalent to E_AGAIN
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

- (BOOL)doInitiateWithRawChannel:(ssh_channel)rawChannel {
    NSAssert([self.session isOnSessionQueue], @"Must be dispatched on session queue");
    
    if (rawChannel) {
        _rawChannel = rawChannel;
    } else {
        _rawChannel = ssh_channel_new(self.session.rawSession);
    }
    
    if (!_rawChannel) return NO;
    
    // Register channle callback right after channel created, since data may comming before we've detected that channel is opened
    [self _registerCallbacks];
    
    return YES;
}

#pragma mark - Properties

- (BOOL)isOpen {
    __block BOOL flag = NO;
    [self.session dispatchSyncOnSessionQueue:^{
        flag = (self.stage == SSHKitChannelStageReady);
    }];
    
    return flag;
}

- (void)setDelegate:(id<SSHKitChannelDelegate>)delegate {
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

#pragma mark - libssh callbacks


/**
 * Reads the first available bytes that become available on the channel.
 **/
static int channel_data_available(ssh_session session,
                                  ssh_channel channel,
                                  void *data,
                                  uint32_t len,
                                  int is_stderr,
                                  void *userdata) {
    SSHKitChannel *selfChannel = (__bridge SSHKitChannel *)userdata;
    NSData *readData = [NSData dataWithBytes:data length:len];
    
    return [selfChannel _didReceiveData:readData isSTDError:is_stderr];
}

static void channel_close_received(ssh_session session,
                                   ssh_channel channel,
                                   void *userdata) {
    SSHKitChannel *selfChannel = (__bridge SSHKitChannel *)userdata;
    [selfChannel doCloseWithError:nil];
}

static void channel_eof_received(ssh_session session,
                                 ssh_channel channel,
                                 void *userdata) {
    SSHKitChannel *selfChannel = (__bridge SSHKitChannel *)userdata;
    [selfChannel doCloseWithError:nil];
}

@end
