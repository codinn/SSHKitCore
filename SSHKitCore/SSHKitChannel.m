#import "SSHKitChannel.h"
#import "SSHKitCore+Protected.h"
#import <libssh/libssh.h>
#import <libssh/callbacks.h>

static struct ssh_channel_callbacks_struct _null_channel_callback = {0};

@interface SSHKitChannel () {
    struct {
        unsigned int didReadStdoutData : 1;
        unsigned int didReadStderrData : 1;
        unsigned int didWriteData : 1;
        unsigned int didOpen : 1;
        unsigned int didCloseWithError : 1;
    } _delegateFlags;
    
    NSData          *_pendingData;
    struct ssh_channel_callbacks_struct _callback;
}

@property (nonatomic, readwrite) SSHKitChannelType  type;
@property (nonatomic, readwrite) SSHKitChannelStage stage;

@property (readwrite) NSString      *directHost;
@property (readwrite) NSUInteger    directPort;

@property (readwrite) NSInteger forwardDestinationPort;

@end

@implementation SSHKitChannel

// -----------------------------------------------------------------------------
#pragma mark - INITIALIZER
// -----------------------------------------------------------------------------

/**
 Create a new SSHKitChannel instance.
 
 @param session A valid, connected, SSHKitSession instance
 @returns New SSHKitChannel instance
 */

- (instancetype)initWithSession:(SSHKitSession *)session channelType:(SSHKitChannelType)channelType delegate:(id<SSHKitChannelDelegate>)aDelegate
{
    if ((self = [super init])) {
        _type = channelType;
        _session = session;
		self.delegate = aDelegate;
        self.stage = SSHKitChannelStageInvalid;
    }

    return self;
}

- (BOOL)isOpened
{
    __block BOOL flag;
    
    __weak SSHKitChannel *weakSelf = self;
    [self.session dispatchSyncOnSessionQueue:^ { @autoreleasepool {
        __strong SSHKitChannel *strongSelf = weakSelf;
        
        flag = strongSelf->_rawChannel && (ssh_channel_is_open(strongSelf->_rawChannel)!=0);
    }}];
    
    return flag;
}

- (void)close
{
    [self closeWithError:nil];
}

- (void)closeWithError:(NSError *)error
{
    __weak SSHKitChannel *weakSelf = self;
    [self.session dispatchAsyncOnSessionQueue:^ { @autoreleasepool {
        __strong SSHKitChannel *strongSelf = weakSelf;
        if (!strongSelf || !strongSelf.session.isConnected) {
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
    ssh_callbacks_init(&_null_channel_callback);
    ssh_set_channel_callbacks(self->_rawChannel, &_null_channel_callback);
    
    ssh_channel_free(self->_rawChannel);
    self->_rawChannel = NULL;
    
    if (_delegateFlags.didCloseWithError) {
        [self.delegate channelDidClose:self withError:error];
    }
    
    [self.session removeChannel:self];
}

- (void)_doProcess {
    NSAssert([self.session isOnSessionQueue], @"Must be dispatched on session queue");
    
    switch (_stage) {
        case SSHKitChannelStageOpening:
            if (_type == SSHKitChannelTypeDirect) {
                [self _doOpenDirect];
            } else if (_type == SSHKitChannelTypeShell) {
                [self _doOpenSession];
            }
            
            break;
            
        case SSHKitChannelStageRequestPTY:
            [self _doRequestPty];
            break;
            
            
        case SSHKitChannelStageRequestShell:
            [self _doRequestShell];
            break;
            
        case SSHKitChannelStageReadWrite:
            [self _tryToWrite];
            break;
            
        case SSHKitChannelStageClosed:
        default:
            break;
    }
}

#pragma mark - shell channel

+ (instancetype)shellChannelFromeSession:(SSHKitSession *)session withTerminalType:(NSString *)terminalType columns:(NSInteger)columns rows:(NSInteger)rows delegate:(id<SSHKitChannelDelegate>)aDelegate
{
    SSHKitChannel *channel = [[self alloc] initWithSession:session channelType:SSHKitChannelTypeShell delegate:aDelegate];
    channel.stage = SSHKitChannelStageAlloced;
    
    [channel.session dispatchAsyncOnSessionQueue: ^{ @autoreleasepool {
        if (!channel.session.isConnected || channel.stage != SSHKitChannelStageAlloced) {
            return_from_block;
        }
        
        if ([channel _doInitiate]) {
            [channel _doOpenSession];
        }
    }}];
    
    return channel;
}

- (void)_doOpenSession {
    int result = ssh_channel_open_session(_rawChannel);
    
    switch (result) {
        case SSH_AGAIN:
            // try again
            break;
            
        case SSH_OK:
            self.stage = SSHKitChannelStageRequestPTY;
            
            // opened
            [self _doRequestPty];
            
            break;
            
        default:
            // open failed
            [self _doCloseWithError:self.session.lastError];
            break;
    }
}

- (void)_doRequestPty {
    int result = ssh_channel_request_pty_size(_rawChannel, "xterm", 80, 24);
    
    switch (result) {
        case SSH_AGAIN:
            // try again
            break;
            
        case SSH_OK:
            self.stage = SSHKitChannelStageRequestShell;
            
            // opened
            [self _doRequestShell];
            
            break;
            
        default:
            // open failed
            [self _doCloseWithError:self.session.lastError];
            break;
    }
}

- (void)_doRequestShell {
    int result = ssh_channel_request_shell(_rawChannel);
    
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
            [self _doCloseWithError:self.session.lastError];
            break;
    }
}

#pragma mark - direct-tcpip channel

+ (instancetype)directChannelFromSession:(SSHKitSession *)session withHost:(NSString *)host port:(NSUInteger)port delegate:(id<SSHKitChannelDelegate>)aDelegate
{
    SSHKitChannel *channel = [[self alloc] initWithSession:session channelType:SSHKitChannelTypeDirect delegate:aDelegate];
    
    channel.stage = SSHKitChannelStageAlloced;
    channel.directHost = host;
    channel.directPort = port;
    
    [channel.session dispatchAsyncOnSessionQueue: ^{ @autoreleasepool {
        if (!channel.session.isConnected || channel.stage != SSHKitChannelStageAlloced) {
            return_from_block;
        }
        
        if ([channel _doInitiate]) {
            [channel _doOpenDirect];
        }
    }}];
    
    return channel;
}

- (void)_doOpenDirect
{
    NSAssert([self.session isOnSessionQueue], @"Must be dispatched on session queue");
    
    int result = ssh_channel_open_forward(_rawChannel, self.directHost.UTF8String, (int)self.directPort, "127.0.0.1", 22);
    
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
            [self _doCloseWithError:self.session.lastError];
            break;
    }
}

- (BOOL)_doInitiate {
    NSAssert([self.session isOnSessionQueue], @"Must be dispatched on session queue");
    
    _rawChannel = ssh_channel_new(self.session.rawSession);
    
    if (!_rawChannel) return NO;
    
    // add channel to session list
    [self.session addChannel:self];
    
    _callback = (struct ssh_channel_callbacks_struct) {
        .userdata               = (__bridge void *)(self),
        .channel_data_function  = channel_data_available,
        .channel_close_function = channel_close_received,
        .channel_eof_function   = channel_eof_received,
    };
    
    ssh_callbacks_init(&_callback);
    ssh_set_channel_callbacks(_rawChannel, &_callback);
    
    self.stage = SSHKitChannelStageOpening;
    
    return YES;
}

- (BOOL)_doInitiateWithRawChannel:(ssh_channel)rawChannel {
    NSAssert([self.session isOnSessionQueue], @"Must be dispatched on session queue");
    
    _rawChannel = rawChannel;
    
    // add channel to session list
    [self.session addChannel:self];
    
    _callback = (struct ssh_channel_callbacks_struct) {
        .userdata               = (__bridge void *)(self),
        .channel_data_function  = channel_data_available,
        .channel_close_function = channel_close_received,
        .channel_eof_function   = channel_eof_received,
    };
    
    ssh_callbacks_init(&_callback);
    ssh_set_channel_callbacks(_rawChannel, &_callback);
    
    self.stage = SSHKitChannelStageOpening;
    
    return YES;
}

#pragma mark - tcpip-forward channel

/** !WARNING!
 tcpip-forward is session global request, requests must go one by one serially.
 Otherwise, forward request will be failed
 */
+ (void)_doRequestRemoteForwardOnSession:(SSHKitSession *)session
{
    NSAssert([session isOnSessionQueue], @"Must be dispatched on session queue");
    
    SSHKitForwardRequest *request = [session firstForwardRequest];
    
    if (!request) {
        return;
    }
    
    int boundport = 0;
    
    int rc = ssh_forward_listen(session.rawSession, request.listenHost.UTF8String, request.listenPort, &boundport);
    
    switch (rc) {
        case SSH_OK:
        {
            // success
            [session removeForwardRequest:request];
            
            // boundport may equals 0, if listenPort is NOT 0.
            boundport = boundport ? boundport : request.listenPort;
            if (request.completionHandler) request.completionHandler(YES, boundport, nil);
            
            // try next
            
            SSHKitForwardRequest *request = [session firstForwardRequest];
            if (request) {
                [self _doRequestRemoteForwardOnSession:session];
            }
        }
            break;
            
        case SSH_AGAIN:
            // try again
            break;
            
        case SSH_ERROR:
        default:
        {
            // failed
            [session removeAllForwardRequest];
            if (request.completionHandler) request.completionHandler(NO, request.listenPort, session.lastError);
        }
            break;
    }
}

+ (void)requestRemoteForwardOnSession:(SSHKitSession *)session withListenHost:(NSString *)host listenPort:(uint16_t)port completionHandler:(SSHKitRequestRemoteForwardCompletionBlock)completionHandler
{
    __weak SSHKitSession *weakSession = session;
    
    [session dispatchAsyncOnSessionQueue: ^{ @autoreleasepool {
        SSHKitSession *strongSession = weakSession;
        if (!strongSession) {
            return_from_block;
        }
        
        if (!strongSession.isConnected) {
            return_from_block;
        }
        
        SSHKitForwardRequest *request = [[SSHKitForwardRequest alloc] initWithListenHost:host port:port completionHandler:completionHandler];
        
        [strongSession addForwardRequest:request];
        
        [self _doRequestRemoteForwardOnSession:strongSession];
    }}];
}

+ (instancetype)_tryCreateForwardChannelFromSession:(SSHKitSession *)session
{
    NSAssert([session isOnSessionQueue], @"Must be dispatched on session queue");
    
    int destination_port = 0;
    ssh_channel rawChannel = ssh_channel_accept_forward(session.rawSession, 0, &destination_port);
    if (!rawChannel) {
        return nil;
    }
    
    SSHKitChannel *channel = [[self alloc] initWithSession:session channelType:SSHKitChannelTypeForward delegate:nil];
    
    channel.forwardDestinationPort = destination_port;
    
    [channel _doInitiateWithRawChannel:rawChannel];
    channel.stage = SSHKitChannelStageReadWrite;
    
    return channel;
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
        
        strongSelf->_pendingData = data;
        
        // resume session write dispatch source
        [strongSelf _tryToWrite];
    }}];
}

NS_INLINE BOOL is_channel_writable(ssh_channel raw_channel) {
    return raw_channel && (ssh_channel_window_size(raw_channel) > 0);
}

- (void)_tryToWrite
{
    NSAssert([self.session isOnSessionQueue], @"Must be dispatched on session queue");
    
    if ( !_pendingData.length || !is_channel_writable(_rawChannel) ) {
        return;
    }
    
    uint32_t datalen = (uint32_t)_pendingData.length;
    
    int wrote = ssh_channel_write(_rawChannel, _pendingData.bytes, datalen);
    
    if ( (wrote < 0) || (wrote>datalen) ) {
        [self _doCloseWithError:self.session.lastError];
        return;
    }
    
    if (wrote==0) {
        return;
    }
    
    if (wrote!=datalen) {
        // libssh resize remote window, it's equivalent to E_AGAIN
        _pendingData = [_pendingData subdataWithRange:NSMakeRange(wrote, datalen-wrote)];
        return;
    }
    
    // all data wrote
    _pendingData = nil;
    
    if (_delegateFlags.didWriteData) {
        [self.delegate channelDidWriteData:self];
    }
}

@end
