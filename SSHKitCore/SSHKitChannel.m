#import "SSHKitChannel.h"
#import "SSHKitCore+Protected.h"
#import <libssh/libssh.h>
#import <libssh/callbacks.h>


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

/**
 Create a new SSHKitChannel instance.
 
 @param session A valid, connected, SSHKitSession instance
 @returns New SSHKitChannel instance
 */
- (instancetype)initWithSession:(SSHKitSession *)session;
- (instancetype)initWithSession:(SSHKitSession *)session delegate:(id<SSHKitChannelDelegate>)aDelegate;

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
		self.delegate = aDelegate;
        self.stage = SSHKitChannelStageCreated;
    }

    return self;
}

- (void)dealloc
{
    [self closeWithError:nil];
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
    [self.session dispatchSyncOnSessionQueue:^ { @autoreleasepool {
        __strong SSHKitChannel *strongSelf = self;
        
        [strongSelf _doCloseWithError:error];
    }}];
}

- (void)_doCloseWithError:(NSError *)error {
    if (self.stage == SSHKitChannelStageClosed) { // already closed
        return;
    }
    
    // SSH_OK or SSH_ERROR, never return SSH_AGAIN
    
    // prevent server receive more then one close message
    if (ssh_channel_is_open(_rawChannel)) {
        ssh_channel_close(_rawChannel);
    }
    
    ssh_channel_free(_rawChannel);
    _rawChannel = NULL;
    
    self.stage = SSHKitChannelStageClosed;
    [self.session removeChannel:self];
    
    if (_delegateFlags.didCloseWithError) {
        [self.delegate channelDidClose:self withError:error];
    }
}

#pragma mark - shell channel

+ (instancetype)shellChannelFromeSession:(SSHKitSession *)session withTerminalType:(NSString *)terminalType columns:(NSInteger)columns rows:(NSInteger)rows delegate:(id<SSHKitChannelDelegate>)aDelegate
{
    __block SSHKitChannel *channel = nil;
    
    [session dispatchSyncOnSessionQueue: ^{ @autoreleasepool {
        if (!session.isConnected) {
            return_from_block;
        }
        
        channel = [[self alloc] initWithSession:session delegate:aDelegate];
        
        if (!channel) {
            return_from_block;
        }
        
        channel.type = SSHKitChannelTypeShell;
        
        channel->_rawChannel = ssh_channel_new(session.rawSession);
        
        // add channel to session list
        [session addChannel:channel];
        
        channel.stage = SSHKitChannelStageOpening1;
        [channel _doOpenSession];
    }}];
    
    return channel;
}

- (void)_doOpenSession
{
    if (self.stage != SSHKitChannelStageOpening1) {
        return;
    }
    
    int result = ssh_channel_open_session(_rawChannel);
    
    switch (result) {
        case SSH_AGAIN:
            // try again
            break;
            
        case SSH_OK:
            self.stage = SSHKitChannelStageOpening2;
            
            // opened
            [self _doRequestPty];
            
            break;
            
        default:
            // open failed
            [self closeWithError:self.session.lastError];
            break;
    }
}

- (void)_doRequestPty
{
    if (self.stage != SSHKitChannelStageOpening2) {
        return;
    }
    
    int result = ssh_channel_request_pty_size(_rawChannel, "xterm", 80, 24);
    
    switch (result) {
        case SSH_AGAIN:
            // try again
            break;
            
        case SSH_OK:
            self.stage = SSHKitChannelStageOpening3;
            
            // opened
            [self _doRequestShell];
            
            break;
            
        default:
            // open failed
            [self closeWithError:self.session.lastError];
            break;
    }
}

- (void)_doRequestShell
{
    if (self.stage != SSHKitChannelStageOpening3) {
        return;
    }
    
    int result = ssh_channel_request_shell(_rawChannel);
    
    switch (result) {
        case SSH_AGAIN:
            // try again
            break;
            
        case SSH_OK:
            self.stage = SSHKitChannelStageReadWrite;
            
            // opened
            [self _didOpen];
            
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

#pragma mark - direct-tcpip channel

+ (instancetype)directChannelFromSession:(SSHKitSession *)session withHost:(NSString *)host port:(NSUInteger)port delegate:(id<SSHKitChannelDelegate>)aDelegate
{
    __block SSHKitChannel *channel = nil;
    
    [session dispatchSyncOnSessionQueue: ^{ @autoreleasepool {
        if (!session.isConnected) {
            return_from_block;
        }
        
        channel = [[self alloc] initWithSession:session delegate:aDelegate];
        
        if (!channel) {
            return_from_block;
        }
        
        channel.directHost = host;
        channel.directPort = port;
        channel.type = SSHKitChannelTypeDirect;
        
        channel->_rawChannel = ssh_channel_new(session.rawSession);
        
        // add channel to session list
        [session addChannel:channel];
        
        channel.stage = SSHKitChannelStageOpening1;
        [channel _doOpenDirect];
    }}];
    
    return channel;
}

- (void)_doOpenDirect
{
    if (self.stage != SSHKitChannelStageOpening1) {
        return;
    }
    
    int result = ssh_channel_open_forward(_rawChannel, self.directHost.UTF8String, (int)self.directPort, "127.0.0.1", 22);
    
    switch (result) {
        case SSH_AGAIN:
            // try again
            break;
            
        case SSH_OK:
            self.stage = SSHKitChannelStageReadWrite;
            
            // opened
            [self _didOpen];
            
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

- (void)_didOpen {
    _callback = (struct ssh_channel_callbacks_struct) {
        .userdata               = (__bridge void *)(self),
        .channel_data_function  = channel_data_available,
        .channel_close_function = channel_close_received,
        .channel_eof_function   = channel_eof_received,
    };
    
    ssh_callbacks_init(&_callback);
    ssh_set_channel_callbacks(_rawChannel, &_callback);
}

#pragma mark - tcpip-forward channel

/** !WARNING!
 tcpip-forward is session global request, requests must go one by one serially.
 Otherwise, forward request will be failed
 */
+ (void)_doRequestRemoteForwardOnSession:(SSHKitSession *)session
{
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
    int destination_port = 0;
    ssh_channel rawChannel = ssh_channel_accept_forward(session.rawSession, 0, &destination_port);
    if (!rawChannel) {
        return nil;
    }
    
    SSHKitChannel *channel = [[self alloc] initWithSession:session];
    
    if (!channel) {
        return nil;
    }
    
    channel.type = SSHKitChannelTypeForward;
    channel.forwardDestinationPort = destination_port;
    channel->_rawChannel = rawChannel;
    channel.stage = SSHKitChannelStageReadWrite;
    
    // add channel to session list
    [session addChannel:channel];
    
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
    if (selfChannel.stage != SSHKitChannelStageReadWrite) {
        return 0;
    }
    
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
        
        if (strongSelf.stage != SSHKitChannelStageReadWrite) {
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
    if ( !_pendingData.length || !is_channel_writable(_rawChannel) ) {
        return;
    }
    
    uint32_t datalen = (uint32_t)_pendingData.length;
    
    int wrote = ssh_channel_write(_rawChannel, _pendingData.bytes, datalen);
    
    if ( (wrote < 0) || (wrote>datalen) ) {
        [self closeWithError:self.session.lastError];
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
