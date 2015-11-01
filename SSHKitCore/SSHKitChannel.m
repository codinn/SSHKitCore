#import "SSHKitChannel.h"
#import "SSHKitCore+Protected.h"
#import <libssh/libssh.h>
#import <libssh/callbacks.h>

typedef struct ssh_channel_callbacks_struct channel_callbacks;

static channel_callbacks s_null_channel_callbacks = {0};

@interface SSHKitChannel () {
    struct {
        unsigned int didReadStdoutData : 1;
        unsigned int didReadStderrData : 1;
        unsigned int didWriteData : 1;
        unsigned int didOpen : 1;
        unsigned int didCloseWithError : 1;
        unsigned int didChangePtySizeToColumnsRows : 1;
    } _delegateFlags;
    
    NSData              *_pendingWriteData;
    channel_callbacks   _callback;
}

@property (nonatomic, readwrite) SSHKitChannelType  type;
@property (nonatomic, readwrite) SSHKitChannelStage stage;

@property (readwrite) NSString      *directHost;
@property (readwrite) NSUInteger    directPort;

@property (readwrite) NSInteger     forwardDestinationPort;

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
    if (self.rawSFTPSession) {
        sftp_free(self.rawSFTPSession);
        _rawSFTPSession = NULL;
    }
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
                [self _openDirect];
            } else if (_type == SSHKitChannelTypeShell) {
                [self _openSession];
            }
            
            break;
            
        case SSHKitChannelStageRequestPTY:
            [self _requestPty];
            break;
            
            
        case SSHKitChannelStageRequestShell:
            [self _requestShell];
            break;
            
        case SSHKitChannelStageReadWrite:
            [self _doWrite];
            break;
            
        case SSHKitChannelStageClosed:
        default:
            break;
    }
}

#pragma mark - sftp Channel

+ (instancetype)sftpChannelFromSession:(SSHKitSession *)session delegate:(id<SSHKitChannelDelegate>)aDelegate {
    SSHKitChannel *channel = [[self alloc] initWithSession:session channelType:SSHKitChannelTypeSFTP delegate:aDelegate];
    channel.stage = SSHKitChannelStageWating;
    [channel.session dispatchAsyncOnSessionQueue: ^{ @autoreleasepool {
        if (!channel.session.isConnected || channel.stage != SSHKitChannelStageWating) {
            if (channel->_delegateFlags.didCloseWithError) {
                [channel.delegate channelDidClose:channel withError:nil];
            }
            return_from_block;
        }
        if ([channel _initiate]) {
            [channel _openSession];
        }
    }}];
    
    return channel;
}

- (void)_requestSFTP {
    int result = ssh_channel_request_sftp(_rawChannel);
    
    switch (result) {
        case SSH_AGAIN:
            // try again
            break;
            
        case SSH_OK:
            if ([self _sftpInit]) {
                self.stage = SSHKitChannelStageReadWrite;
                [self _registerCallbacks];
                // opened
            if (_delegateFlags.didOpen) {
                [self.delegate channelDidOpen:self];
            }
            } else {
                [self _doCloseWithError:self.session.coreError];
                [self.session disconnectIfNeeded];
            }
            break;
        default:
            // open failed
            [self _doCloseWithError:self.session.coreError];
            [self.session disconnectIfNeeded];
            break;
    }
}

- (BOOL)_sftpInit {
    _rawSFTPSession = sftp_new_channel(self.session.rawSession, self.rawChannel);
    if (self.rawSFTPSession == NULL) {
        // NSLog(@(ssh_get_error(session.rawSession)));
        return NO;
    }
    int rc = sftp_init(_rawSFTPSession);
    if (rc != SSH_OK) {
        // fprintf(stderr, "Error initializing SFTP session: %s.\n", sftp_get_error(sftp));
        sftp_free(_rawSFTPSession);
        _rawSFTPSession = NULL;
        // return rc;
        return NO;
    }
    return YES;
}

#pragma mark - shell Channel

+ (instancetype)shellChannelFromSession:(SSHKitSession *)session withTerminalType:(NSString *)terminalType columns:(NSInteger)columns rows:(NSInteger)rows delegate:(id<SSHKitChannelDelegate>)aDelegate
{
    SSHKitChannel *channel = [[self alloc] initWithSession:session channelType:SSHKitChannelTypeShell delegate:aDelegate];
    channel.stage = SSHKitChannelStageWating;
    
    [channel.session dispatchAsyncOnSessionQueue: ^{ @autoreleasepool {
        if (!channel.session.isConnected || channel.stage != SSHKitChannelStageWating) {
            if (channel->_delegateFlags.didCloseWithError) {
                [channel.delegate channelDidClose:channel withError:nil];
            }
            
            return_from_block;
        }
        
        if ([channel _initiate]) {
            channel->_shellColumns = columns;
            channel->_shellRows = rows;
            [channel _openSession];
        }
    }}];
    
    return channel;
}

- (void)_openSession {
    int result = ssh_channel_open_session(_rawChannel);
    
    switch (result) {
        case SSH_AGAIN:
            // try again
            break;
        case SSH_OK:
            if (_type == SSHKitChannelTypeSFTP) {
                self.stage = SSHKitChannelStageRequestPTY;
                [self _requestSFTP];
            } else {
                self.stage = SSHKitChannelStageRequestSFTP;
                // opened
                [self _requestPty];
            }
            break;
        default:
            // open failed
            [self _doCloseWithError:self.session.coreError];
            [self.session disconnectIfNeeded];
            break;
    }
}

- (void)_requestPty {
    int result = ssh_channel_request_pty_size(_rawChannel, "xterm", (int)_shellColumns, (int)_shellRows);
    
    switch (result) {
        case SSH_AGAIN:
            // try again
            break;
            
        case SSH_OK:
            self.stage = SSHKitChannelStageRequestShell;
            
            // opened
            [self _requestShell];
            
            break;
            
        default:
            // open failed
            [self _doCloseWithError:self.session.coreError];
            [self.session disconnectIfNeeded];
            break;
    }
}

- (void)_requestShell {
    int result = ssh_channel_request_shell(_rawChannel);
    
    switch (result) {
        case SSH_AGAIN:
            // try again
            break;
            
        case SSH_OK:
            self.stage = SSHKitChannelStageReadWrite;
            [self _registerCallbacks];
            
            // opened
            if (_delegateFlags.didOpen) {
                [self.delegate channelDidOpen:self];
            }
            break;
            
        default:
            // open failed
            [self _doCloseWithError:self.session.coreError];
            [self.session disconnectIfNeeded];
            break;
    }
}

#pragma mark - direct-tcpip Channel

+ (instancetype)directChannelFromSession:(SSHKitSession *)session withHost:(NSString *)host port:(NSUInteger)port delegate:(id<SSHKitChannelDelegate>)aDelegate
{
    SSHKitChannel *channel = [[self alloc] initWithSession:session channelType:SSHKitChannelTypeDirect delegate:aDelegate];
    
    channel.stage = SSHKitChannelStageWating;
    channel.directHost = host;
    channel.directPort = port;
    
    [channel.session dispatchAsyncOnSessionQueue: ^{ @autoreleasepool {
        if (!channel.session.isConnected || channel.stage != SSHKitChannelStageWating) {
            if (channel->_delegateFlags.didCloseWithError) {
                [channel.delegate channelDidClose:channel withError:nil];
            }
            
            return_from_block;
        }
        
        if ([channel _initiate]) {
            [channel _openDirect];
        }
    }}];
    
    return channel;
}

- (void)_openDirect
{
    NSAssert([self.session isOnSessionQueue], @"Must be dispatched on session queue");
    
    int result = ssh_channel_open_forward(_rawChannel, self.directHost.UTF8String, (int)self.directPort, "127.0.0.1", 22);
    
    switch (result) {
        case SSH_AGAIN:
            // try again
            break;
            
        case SSH_OK:
            self.stage = SSHKitChannelStageReadWrite;
            [self _registerCallbacks];
            // opened
            if (_delegateFlags.didOpen) {
                [self.delegate channelDidOpen:self];
            }
            break;
        default: {
            // open failed
            // [self _doCloseWithError:self.session.lastError];
            NSError *error = [NSError errorWithDomain:SSHKitCoreErrorDomain
                                      code:SSHKitErrorConnectFailure
                                  userInfo:@{ NSLocalizedDescriptionKey : @"Open Direct Failed" }];
            if (self.session.coreError) {
                error = self.session.coreError;
            }
            [self _doCloseWithError:error];  // self.session.lastError
            [self.session disconnectIfNeeded];
            break;
        }
    }
}

#pragma mark - tcpip-forward Channel

/** !WARNING!
 tcpip-forward is session global request, requests must go one by one serially.
 Otherwise, forward request will be failed
 */
+ (void)_doRequestRemoteForwardOnSession:(SSHKitSession *)session
{
    NSAssert([session isOnSessionQueue], @"Must be dispatched on session queue");
    
    SSHKitForwardRequest *request = [session firstForwardRequest];
    
    if (!request) return;
    
    int boundport = 0;
    
    int rc = ssh_channel_listen_forward(session.rawSession, request.listenHost.UTF8String, request.listenPort, &boundport);
    
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
        default: {
            // failed
            [session removeAllForwardRequest];
            
            if (request.completionHandler) {
                NSError *error = session.coreError;
                error = [NSError errorWithDomain:error.domain code:SSHKitErrorChannelFailure userInfo:error.userInfo];
                request.completionHandler(NO, request.listenPort, error);
            }
            
            [session disconnectIfNeeded];
        }
            break;
    }
}

+ (void)requestRemoteForwardOnSession:(SSHKitSession *)session withListenHost:(NSString *)host listenPort:(uint16_t)port completionHandler:(SSHKitRequestRemoteForwardCompletionBlock)completionHandler
{
    __weak SSHKitSession *weakSession = session;
    
    [session dispatchAsyncOnSessionQueue: ^{ @autoreleasepool {
        SSHKitSession *strongSession = weakSession;
        if (!strongSession.isConnected) {
            return_from_block;
        }
        
        SSHKitForwardRequest *request = [[SSHKitForwardRequest alloc] initWithListenHost:host port:port completionHandler:completionHandler];
        
        [strongSession addForwardRequest:request];
        
        [self _doRequestRemoteForwardOnSession:strongSession];
    }}];
}

+ (instancetype)_doCreateForwardChannelFromSession:(SSHKitSession *)session
{
    NSAssert([session isOnSessionQueue], @"Must be dispatched on session queue");
    
    int destination_port = 0;
    ssh_channel rawChannel = ssh_channel_accept_forward(session.rawSession, 0, &destination_port);
    if (!rawChannel) {
        return nil;
    }
    
    SSHKitChannel *channel = [[self alloc] initWithSession:session channelType:SSHKitChannelTypeForward delegate:nil];
    
    channel.forwardDestinationPort = destination_port;
    
    [channel _initiateWithRawChannel:rawChannel];
    
    channel.stage = SSHKitChannelStageReadWrite;
    [channel _registerCallbacks];
    
    return channel;
}


#pragma mark - Read / Write

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

- (void)_doWrite
{
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

- (void)changePtySizeToColumns:(NSInteger)columns rows:(NSInteger)rows {
    __weak SSHKitChannel *weakSelf = self;
    
    [self.session dispatchAsyncOnSessionQueue:^{ @autoreleasepool {
        __strong SSHKitChannel *strongSelf = weakSelf;
        
        if (strongSelf.stage != SSHKitChannelStageReadWrite || !strongSelf.session.isConnected || strongSelf.type!=SSHKitChannelTypeShell) {
            return_from_block;
        }
        
        int rc = ssh_channel_change_pty_size(strongSelf->_rawChannel, (int)columns, (int)rows);
        
        if (!strongSelf->_delegateFlags.didChangePtySizeToColumnsRows) {
            return;
        }
        
        NSError *error = nil;
        
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
