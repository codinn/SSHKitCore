#import "SSHKitSession.h"
#import "SSHKitCore+Protected.h"
#import <libssh/libssh.h>
#import <libssh/callbacks.h>
#import <libssh/server.h>
#import "SSHKitConnector.h"
#import "SSHKitSession+Channels.h"
#import "SSHKitPrivateKeyParser.h"
#import "SSHKitForwardChannel.h"

#define SOCKET_NULL -1

typedef NS_ENUM(NSInteger, SSHKitSessionStage) {
    SSHKitSessionStageUnknown   = 0,
    SSHKitSessionStageNotConnected,
    SSHKitSessionStageOpeningSocket,
    SSHKitSessionStageConnecting,
    SSHKitSessionStagePreAuthenticate,
    SSHKitSessionStageAuthenticating,
    SSHKitSessionStageAuthenticated,
    SSHKitSessionStageDisconnected,
};

@interface SSHKitSession () {
	struct {
		unsigned int keyboardInteractiveRequest     : 1;
		unsigned int didConnectToHostPort           : 1;
		unsigned int didDisconnectWithError         : 1;
		unsigned int shouldConnectWithHostKey       : 1;
        unsigned int didReceiveIssueBanner          : 1;
        unsigned int authenticateWithAllowedMethodsPartialSuccess : 1;
        unsigned int didAuthenticateUser            : 1;
        unsigned int didOpenForwardChannel          : 1;
	} _delegateFlags;
    
    dispatch_source_t   _socketReadSource;
    dispatch_source_t   _keepAliveTimer;
    NSInteger           _keepAliveCounter;
    
    dispatch_block_t    _authBlock;
    
    void *_isOnSessionQueueKey;
    
    SSHKitConnector     *_connector;
}

@property (nonatomic, readwrite)  SSHKitSessionStage stage;
@property (nonatomic, readwrite)  NSString    *host;
@property (nonatomic, readwrite)  uint16_t    port;
@property (nonatomic, readwrite)  NSString    *username;

@property (nonatomic, readwrite)  NSString    *clientBanner;
@property (nonatomic, readwrite)  NSString    *serverBanner;
@property (nonatomic, readwrite)  NSString    *protocolVersion;

@property (nonatomic, readonly) long          timeout;

@property (nonatomic, readonly) dispatch_queue_t sessionQueue;

// connect over proxy
@property (nonatomic) SSHKitProxyType proxyType;
@property (nonatomic, copy) NSString  *proxyHost;
@property (nonatomic)       uint16_t  proxyPort;
@property (nonatomic, copy) NSString  *proxyUsername;
@property (nonatomic, copy) NSString  *proxyPassword;
@end

#pragma mark -

@implementation SSHKitSession

+ (void)initialize {
    SSHKitCoreInitiate();
}

- (instancetype)init {
	return [self initWithDelegate:nil sessionQueue:NULL];
}

- (instancetype)initWithDelegate:(id<SSHKitSessionDelegate>)aDelegate {
	return [self initWithDelegate:aDelegate sessionQueue:NULL];
}

- (instancetype)initWithDelegate:(id<SSHKitSessionDelegate>)aDelegate sessionQueue:(dispatch_queue_t)sq {
    if ((self = [super init])) {
        self.enableCompression = NO;
        self.enableIPv4 = YES;
        self.enableIPv6 = YES;
        
        self.stage = SSHKitSessionStageNotConnected;
        _channels = [@[] mutableCopy];
        _forwardRequests = [@[] mutableCopy];
        self.proxyType = SSHKitProxyTypeDirect;
        
		self.delegate = aDelegate;
		
		if (sq) {
			NSAssert(sq != dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_LOW, 0),
			         @"The given socketQueue parameter must not be a concurrent queue.");
			NSAssert(sq != dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_HIGH, 0),
			         @"The given socketQueue parameter must not be a concurrent queue.");
			NSAssert(sq != dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0),
			         @"The given socketQueue parameter must not be a concurrent queue.");
			
			_sessionQueue = sq;
		} else {
			_sessionQueue = dispatch_queue_create("com.codinn.libssh.session_queue", DISPATCH_QUEUE_SERIAL);
		}
        
		// The dispatch_queue_set_specific() and dispatch_get_specific() functions take a "void *key" parameter.
		// From the documentation:
		//
		// > Keys are only compared as pointers and are never dereferenced.
		// > Thus, you can use a pointer to a static variable for a specific subsystem or
		// > any other value that allows you to identify the value uniquely.
		//
		// We're just going to use the memory address of an ivar.
		// Specifically an ivar that is explicitly named for our purpose to make the code more readable.
		//
		// However, it feels tedious (and less readable) to include the "&" all the time:
		// dispatch_get_specific(&IsOnSocketQueueOrTargetQueueKey)
		//
		// So we're going to make it so it doesn't matter if we use the '&' or not,
		// by assigning the value of the ivar to the address of the ivar.
		// Thus: IsOnSocketQueueOrTargetQueueKey == &IsOnSocketQueueOrTargetQueueKey;
		
		_isOnSessionQueueKey = &_isOnSessionQueueKey;
		
		void *nonNullUnusedPointer = (__bridge void *)self;
		dispatch_queue_set_specific(_sessionQueue, _isOnSessionQueueKey, nonNullUnusedPointer, NULL);
    }
    
    return self;
}

- (void)dealloc {
    // Synchronous disconnection
    [self dispatchSyncOnSessionQueue: ^{ @autoreleasepool {
        [self _doDisconnectWithError:nil];
    }}];
}

-(NSString *)description {
    return [NSString stringWithFormat:@"%@@%@:%d", self.username, self.host, self.port];
}

#pragma mark Configuration

- (void)setDelegate:(id<SSHKitSessionDelegate>)delegate {
	if (_delegate != delegate) {
		_delegate = delegate;
        _delegateFlags.authenticateWithAllowedMethodsPartialSuccess = [delegate respondsToSelector:@selector(session:authenticateWithAllowedMethods:partialSuccess:)];
		_delegateFlags.didConnectToHostPort = [delegate respondsToSelector:@selector(session:didConnectToHost:port:)];
		_delegateFlags.didDisconnectWithError = [delegate respondsToSelector:@selector(session:didDisconnectWithError:)];
		_delegateFlags.keyboardInteractiveRequest = [delegate respondsToSelector:@selector(session:keyboardInteractiveRequest:)];
        _delegateFlags.shouldConnectWithHostKey = [delegate respondsToSelector:@selector(session:shouldConnectWithHostKey:)];
        _delegateFlags.didReceiveIssueBanner = [delegate respondsToSelector:@selector(session:didReceiveIssueBanner:)];
        _delegateFlags.didOpenForwardChannel = [delegate respondsToSelector:@selector(session:didOpenForwardChannel:)];
        _delegateFlags.didAuthenticateUser = [delegate respondsToSelector:@selector(session:didAuthenticateUser:)];
	}
}

// -----------------------------------------------------------------------------
#pragma mark Connecting
// -----------------------------------------------------------------------------

- (void)_doConnect {
    int result = ssh_connect(_rawSession);
    
    switch (result) {
        case SSH_OK: {
            // connection established
            const char *clientbanner = ssh_get_clientbanner(self.rawSession);
            if (clientbanner) self.clientBanner = @(clientbanner);
            
            if (_logDebug) _logDebug(@"Client banner: %@", self.clientBanner);
            
            const char *serverbanner = ssh_get_serverbanner(self.rawSession);
            if (serverbanner) self.serverBanner = @(serverbanner);
            
            if (_logDebug) _logDebug(@"Server banner: %@", self.serverBanner);
            
            int ver = ssh_get_version(self.rawSession);
            
            if (ver>0) {
                self.protocolVersion = @(ver).stringValue;
            }
            
            if (_delegateFlags.didConnectToHostPort) {
                [self.delegate session:self didConnectToHost:self.host port:self.port];
            }
            
            // check host key
            NSError *error = nil;
            SSHKitHostKey *hostKey = [SSHKitHostKey parserFromSession:self error:&error];
            
            if ( !error && ! (_delegateFlags.shouldConnectWithHostKey && [self.delegate session:self shouldConnectWithHostKey:hostKey]) )
            {
                // failed
                error = [NSError errorWithDomain:SSHKitCoreErrorDomain
                                            code:SSHKitErrorHostKeyMismatch
                                        userInfo:@{ NSLocalizedDescriptionKey : @"Server host key verification failed" }];
            }
            
            if (error) {
                [self _doDisconnectWithError:error];
                return;
            }
            
            self.stage = SSHKitSessionStagePreAuthenticate;
            [self _preAuthenticate];
        }
            break;
            
        case SSH_AGAIN:
            // try again
            break;
            
        default: {
            [self _doDisconnectWithError:self.coreError];
        }
            break;
            
    }
}

- (void)connectToHost:(NSString *)host onPort:(uint16_t)port withUser:(NSString*)user {
    [self connectToHost:host onPort:port viaInterface:nil withUser:(NSString*)user timeout:0.0];
}

- (void)connectToHost:(NSString *)host onPort:(uint16_t)port withUser:(NSString *)user timeout:(NSTimeInterval)timeout {
    [self connectToHost:host onPort:port viaInterface:nil withUser:(NSString*)user timeout:timeout];
}

- (void)connectToHost:(NSString *)host onPort:(uint16_t)port viaInterface:(NSString *)interface withUser:(NSString*)user timeout:(NSTimeInterval)timeout {
    self.host = [host copy];
    self.port = port;
    self.username = [user copy];
    _timeout = (long)timeout;
    
    __weak SSHKitSession *weakSelf = self;
    [self dispatchAsyncOnSessionQueue: ^{ @autoreleasepool {
        __strong SSHKitSession *strongSelf = weakSelf;
        if (!strongSelf) {
            return_from_block;
        }
        
        // disconnect if connected
        if (strongSelf.isConnected) {
            [strongSelf _doDisconnectWithError:nil];
        }
        
        strongSelf->_rawSession = ssh_new();
        
        [strongSelf _registerLogCallback];
        
        if (!strongSelf->_rawSession) {
            [strongSelf _doDisconnectWithError:[NSError errorWithDomain:SSHKitCoreErrorDomain code:SSHKitErrorStop userInfo:@{ NSLocalizedDescriptionKey : @"Failed to create SSH session" }]];
            return_from_block;
        }
        
        if (!strongSelf->_connector) {
            if (strongSelf.proxyType > SSHKitProxyTypeDirect) {
                // connect over a proxy server
                
                if (strongSelf->_logDebug) strongSelf->_logDebug(@"Connect through proxy with type %d", strongSelf.proxyType);
                
                id ConnectProxyClass = SSHKitConnectorProxy.class;
                
                switch (strongSelf.proxyType) {
                    case SSHKitProxyTypeHTTP:
                    case SSHKitProxyTypeHTTPS:
                        ConnectProxyClass = SSHKitConnectorHTTPS.class;
                        break;
                        
                    case SSHKitProxyTypeSOCKS4:
                        ConnectProxyClass = SSHKitConnectorSOCKS4.class;
                        break;
                        
                    case SSHKitProxyTypeSOCKS4A:
                        ConnectProxyClass = SSHKitConnectorSOCKS4A.class;
                        break;
                        
                    case SSHKitProxyTypeSOCKS5:
                    default:
                        ConnectProxyClass = SSHKitConnectorSOCKS5.class;
                        break;
                }
                
                if (strongSelf.proxyUsername.length) {
                    strongSelf->_connector = [[ConnectProxyClass alloc] initWithProxyHost:strongSelf.proxyHost port:strongSelf.proxyPort username:strongSelf.proxyUsername password:strongSelf.proxyPassword];
                } else {
                    strongSelf->_connector = [[ConnectProxyClass alloc] initWithProxyHost:strongSelf.proxyHost port:strongSelf.proxyPort];
                }
            } else {
                if (strongSelf->_logDebug) strongSelf->_logDebug(@"Connect directly");
                // connect directly
                strongSelf->_connector = [[SSHKitConnector alloc] init];
            }
            
            // configure ipv4/ipv6
            strongSelf->_connector.IPv4Enabled = strongSelf.enableIPv4;
            strongSelf->_connector.IPv6Enabled = strongSelf.enableIPv6;
            
            if (strongSelf.logDebug) {
                strongSelf->_connector.logDebug = strongSelf.logDebug;
            }
            
            strongSelf.stage = SSHKitSessionStageOpeningSocket;
            
            NSError *error = nil;
            [strongSelf->_connector connectToHost:host onPort:port viaInterface:interface withTimeout:strongSelf.timeout error:&error];
            
            if (error) {
                [strongSelf _doDisconnectWithError:error];
                return_from_block;
            }
        }
        
        int socket = strongSelf->_connector.socketFD;
        ssh_options_set(strongSelf->_rawSession, SSH_OPTIONS_FD, &socket);
        
        // compression
        
        if (strongSelf.enableCompression) {
            ssh_options_set(strongSelf->_rawSession, SSH_OPTIONS_COMPRESSION, "yes");
        } else {
            ssh_options_set(strongSelf->_rawSession, SSH_OPTIONS_COMPRESSION, "no");
        }
        
        // ciphers
        if (strongSelf.ciphers.length) {
            ssh_options_set(strongSelf->_rawSession, SSH_OPTIONS_CIPHERS_C_S, strongSelf.ciphers.UTF8String);
            ssh_options_set(strongSelf->_rawSession, SSH_OPTIONS_CIPHERS_S_C, strongSelf.ciphers.UTF8String);
        }
        
        // host key algorithms
        if (strongSelf.keyExchangeAlgorithms.length) {
            ssh_options_set(strongSelf->_rawSession, SSH_OPTIONS_KEY_EXCHANGE, strongSelf.keyExchangeAlgorithms.UTF8String);
        }
        
        // host key algorithms
        if (strongSelf.hostKeyAlgorithms.length) {
            ssh_options_set(strongSelf->_rawSession, SSH_OPTIONS_HOSTKEYS, strongSelf.hostKeyAlgorithms.UTF8String);
        }
        
        // tcp keepalive
        if ( strongSelf.serverAliveCountMax<=0 ) {
            int on = 1;
            if (strongSelf->_logDebug) strongSelf->_logDebug(@"Enable TCP keepalive");
            setsockopt(socket, SOL_SOCKET, SO_KEEPALIVE, (void *)&on, sizeof(on));
        }
        
        ssh_options_set(strongSelf->_rawSession, SSH_OPTIONS_USER, strongSelf.username.UTF8String);
#if DEBUG
        int verbosity = SSH_LOG_FUNCTIONS;
#else
        int verbosity = SSH_LOG_NOLOG;
#endif
        ssh_options_set(strongSelf->_rawSession, SSH_OPTIONS_LOG_VERBOSITY, &verbosity);
        
        if (strongSelf->_timeout > 0) {
            ssh_options_set(strongSelf->_rawSession, SSH_OPTIONS_TIMEOUT, &strongSelf->_timeout);
        }
        
        // set to non-blocking mode
        ssh_set_blocking(strongSelf->_rawSession, 0);
        
        strongSelf.stage = SSHKitSessionStageConnecting;
        [strongSelf _setupSocketReadSource];
        [strongSelf _doConnect];
    }}];
}

- (void)dispatchSyncOnSessionQueue:(dispatch_block_t)block {
    dispatch_block_t _logSafeBlock = ^ {
        [self _registerLogCallback];
        block();
    };
    
    if (dispatch_get_specific(_isOnSessionQueueKey))
        _logSafeBlock();
    else
        dispatch_sync(_sessionQueue, _logSafeBlock);
}
- (void)dispatchAsyncOnSessionQueue:(dispatch_block_t)block
{
    dispatch_block_t _logSafeBlock = ^ {
        [self _registerLogCallback];
        block();
    };
    
    dispatch_async(_sessionQueue, _logSafeBlock);
}

- (BOOL)isOnSessionQueue {
    return dispatch_get_specific(_isOnSessionQueueKey) != NULL;
}

// -----------------------------------------------------------------------------
#pragma mark Disconnecting
// -----------------------------------------------------------------------------

- (BOOL)isDisconnected {
    return (_stage == SSHKitSessionStageNotConnected) || (_stage == SSHKitSessionStageUnknown) || (_stage ==SSHKitSessionStageDisconnected);
}

- (BOOL)isConnected {
    return _stage == SSHKitSessionStageAuthenticated;
}

- (void)disconnect {
    [self disconnectWithError:nil];
}

- (void)disconnectWithError:(NSError *)error {
    __weak SSHKitSession *weakSelf = self;
    
    // Asynchronous disconnection, as documented in the header file
    [self dispatchAsyncOnSessionQueue: ^{ @autoreleasepool {
        __strong SSHKitSession *strongSelf = weakSelf;
        if (!strongSelf) {
            return_from_block;
        }
        
        [strongSelf _doDisconnectWithError:error];
    }}];
}

- (void)impoliteDisconnect
{
    if (_connector) {
        [_connector disconnect];
    }
    
    [self disconnect];
}

- (void)_doDisconnectWithError:(NSError *)error {
    if (self.isDisconnected) { // already disconnected
        return;
    }
    
    _stage = SSHKitSessionStageDisconnected;
    
    [self _cancelKeepAliveTimer];
    
    NSArray *channels = [_channels copy];
    for (SSHKitChannel* channel in channels) {
        [channel doCloseWithError:nil];
    }
    
    [_channels removeAllObjects];
    
    if (ssh_is_connected(_rawSession)) {
        ssh_disconnect(_rawSession);
    }
    
    ssh_free(_rawSession);
    _rawSession = NULL;
    
    [self _cancelSocketReadSource];
    
    if (_connector) {
        [_connector disconnect];
        _connector = nil;
    }
    
    if (_delegateFlags.didDisconnectWithError) {
        [self.delegate session:self didDisconnectWithError:error];
    }
}

#pragma mark Diagnostics

- (NSString *)hostIP {
    if (self.proxyHost.length) { // connect over a proxy
        return nil;
    }
    
    // _connector will be nil if use a custom socket fd
    return _connector.connectedHost;
}

- (NSError *)coreError {
    if(!_rawSession) {
        return nil;
    }
    
    __block NSError *error;
    
    [self dispatchSyncOnSessionQueue :^{ @autoreleasepool {
        int code = ssh_get_error_code(self->_rawSession);
        
        if (code == SSHKitErrorNoError) {
            return_from_block;
        }
        
        const char* errorStr = ssh_get_error(self->_rawSession);
        
        error = [NSError errorWithDomain:SSHKitLibsshErrorDomain
                                   code:code
                                userInfo: errorStr ? @{ NSLocalizedDescriptionKey : @(errorStr) } : nil];
    }}];
    
    return error;
}

- (void)disconnectIfNeeded {
    [self dispatchSyncOnSessionQueue :^{ @autoreleasepool {
        if (!self->_rawSession) {
            return_from_block;
        }
        
        if (!ssh_is_connected(self->_rawSession)) {
            [self _doDisconnectWithError:self.coreError];
        }
    }}];
}

// -----------------------------------------------------------------------------
#pragma mark Authentication
// -----------------------------------------------------------------------------

- (NSArray *)_getUserAuthList {
    NSMutableArray *authMethods = [@[] mutableCopy];
    int authList = ssh_userauth_list(_rawSession, NULL);
    
    // WARN: ssh_set_auth_methods only available on server api,
    // it's a dirty hack for support multi-factor auth
    ssh_set_auth_methods(_rawSession, 0);
    
    if (authList & SSH_AUTH_METHOD_PASSWORD) {
        [authMethods addObject:@"password"];
    }
    if (authList & SSH_AUTH_METHOD_PUBLICKEY) {
        [authMethods addObject:@"publickey"];
    }
    if (authList & SSH_AUTH_METHOD_HOSTBASED) {
        [authMethods addObject:@"hostbased"];
    }
    if (authList & SSH_AUTH_METHOD_INTERACTIVE) {
        [authMethods addObject:@"keyboard-interactive"];
    }
    if (authList & SSH_AUTH_METHOD_GSSAPI_MIC) {
        [authMethods addObject:@"gssapi-with-mic"];
    }
    
    return [authMethods copy];
}

- (void)_preAuthenticate {
    // must call this method before next auth method, or libssh will be failed
    int rc = ssh_userauth_none(_rawSession, NULL);
    
    switch (rc) {
        case SSH_AUTH_AGAIN:
            // try again
            break;
            
        case SSH_AUTH_DENIED: {
            // pre auth success
            if (_delegateFlags.didReceiveIssueBanner) {
                /*
                 *** Does not work without calling ssh_userauth_none() first ***
                 *** That will be fixed ***
                 */
                const char *banner = ssh_get_issue_banner(_rawSession);
                if (banner) [self.delegate session:self didReceiveIssueBanner:@(banner)];
            }
            
            NSArray *authMethods = [self _getUserAuthList];
            
            if (_delegateFlags.authenticateWithAllowedMethodsPartialSuccess) {
                NSError *error = [self.delegate session:self authenticateWithAllowedMethods:authMethods partialSuccess:NO];
                if (error) {
                    [self _doDisconnectWithError:error];
                }
                
                // Handoff to next auth method
                return;
            }
        }
            
        default:
            [self _checkAuthenticateResult:rc];
            break;
    }
}

- (void)_didAuthenticate {
    self.stage = SSHKitSessionStageAuthenticated;
    
    // start diagnoses timer
    [self _setupKeepAliveTimer];
    
    if (_delegateFlags.didAuthenticateUser) {
        [self.delegate session:self didAuthenticateUser:nil];
    }
}

- (void)_checkAuthenticateResult:(NSInteger)result {
    switch (result) {
        case SSH_AUTH_DENIED:
            [self _doDisconnectWithError:self.coreError];
            return;
            
        case SSH_AUTH_ERROR:
            [self _doDisconnectWithError:self.coreError];
            return;
            
        case SSH_AUTH_SUCCESS:
            [self _didAuthenticate];
            return;
            
        case SSH_AUTH_PARTIAL: {
            // pre auth success
            NSArray *authMethods = [self _getUserAuthList];
            
            if (_delegateFlags.authenticateWithAllowedMethodsPartialSuccess) {
                NSError *error = [self.delegate session:self authenticateWithAllowedMethods:authMethods partialSuccess:YES];
                if (error) {
                    [self _doDisconnectWithError:error];
                }
                
                // Handoff to next auth method
                return;
            }
        }
            return;
            
        case SSH_AUTH_AGAIN: // should never come here
        default:
            [self _doDisconnectWithError:[NSError errorWithDomain:SSHKitCoreErrorDomain
                                                          code:SSHKitErrorAuthFailure
                                                      userInfo:@{ NSLocalizedDescriptionKey : @"Unknown error while authenticate user"} ]];
            return;
    }
}


- (void)authenticateByInteractiveHandler:(NSArray *(^)(NSInteger, NSString *, NSString *, NSArray *))interactiveHandler {
    self.stage = SSHKitSessionStageAuthenticating;

    __block NSInteger index = 0;
    __block int rc = SSH_AUTH_AGAIN;
    
    __weak SSHKitSession *weakSelf = self;
    _authBlock = ^{ @autoreleasepool {
        __strong SSHKitSession *strongSelf = weakSelf;
        if (!strongSelf) {
            return_from_block;
        }
        
        // try keyboard-interactive method
        if (rc==SSH_AUTH_AGAIN) {
            rc = ssh_userauth_kbdint(strongSelf->_rawSession, NULL, NULL);
        }
        
        switch (rc) {
            case SSH_AUTH_AGAIN:
                // try again
                return_from_block;
                
            case SSH_AUTH_INFO: {
                const char* name = ssh_userauth_kbdint_getname(strongSelf->_rawSession);
                NSString *nameString = name ? @(name) : nil;
                
                const char* instruction = ssh_userauth_kbdint_getinstruction(strongSelf->_rawSession);
                NSString *instructionString = instruction ? @(instruction) : nil;
                
                int nprompts = ssh_userauth_kbdint_getnprompts(strongSelf->_rawSession);
                
                if (nprompts>0) { // getnprompts may return zero
                    NSMutableArray *prompts = [@[] mutableCopy];
                    for (int i = 0; i < nprompts; i++) {
                        char echo = NO;
                        const char *prompt = ssh_userauth_kbdint_getprompt(strongSelf->_rawSession, i, &echo);
                        
                        NSString *promptString = prompt ? @(prompt) : @"";
                        [prompts addObject:@[promptString, @(echo)]];
                    }
                    
                    NSArray *information = interactiveHandler(index, nameString, instructionString, prompts);
                    
                    for (int i = 0; i < information.count; i++) {
                        if (ssh_userauth_kbdint_setanswer(strongSelf->_rawSession, i, [information[i] UTF8String]) < 0)
                        {
                            // failed
                            break;
                        }
                    }
                }
                
                index ++;
            }
                // send and check again
                rc = ssh_userauth_kbdint(strongSelf->_rawSession, NULL, NULL);
                return_from_block;
                
            default:
                break;
        }
        
        [strongSelf _checkAuthenticateResult:rc];
    }};
    
    [self dispatchAsyncOnSessionQueue:_authBlock];
}

- (void)authenticateByPasswordHandler:(NSString *(^)(void))passwordHandler {
    NSString *password = passwordHandler();
    
    self.stage = SSHKitSessionStageAuthenticating;
    
    __weak SSHKitSession *weakSelf = self;
    _authBlock = ^{ @autoreleasepool {
        __strong SSHKitSession *strongSelf = weakSelf;
        if (!strongSelf) {
            return_from_block;
        }
        
        // try "password" method, which is deprecated in SSH 2.0
        int rc = ssh_userauth_password(strongSelf->_rawSession, NULL, password.UTF8String);
        
        if (rc == SSH_AUTH_AGAIN) {
            // try again
            return;
        }
        
        [strongSelf _checkAuthenticateResult:rc];
    }};
    
    [self dispatchAsyncOnSessionQueue: _authBlock];
}

- (void)authenticateByPrivateKeyBase64:(NSString *)base64 {
    SSHKitPrivateKeyParser *parser = [SSHKitPrivateKeyParser parserFromBase64:base64 withPassphraseHandler:NULL error:nil];
    if (parser) {
        [self authenticateByPrivateKeyParser:parser];
    }
    
}

- (void)authenticateByPrivateKeyParser:(SSHKitPrivateKeyParser *)parser {
    self.stage = SSHKitSessionStageAuthenticating;
    
    __block BOOL publicKeySuccess = NO;
    __weak SSHKitSession *weakSelf = self;
    
    _authBlock = ^{ @autoreleasepool {
        __strong SSHKitSession *strongSelf = weakSelf;
        if (!strongSelf) {
            return_from_block;
        }
        
        if (!publicKeySuccess) {
            // try public key
            int ret = ssh_userauth_try_publickey(strongSelf->_rawSession, NULL, parser.publicKey);
            switch (ret) {
                case SSH_AUTH_AGAIN:
                    // try again
                    return;
                    
                case SSH_AUTH_SUCCESS:
                    // try private key
                    break;
                    
                default:
                    [strongSelf _checkAuthenticateResult:ret];
                    return_from_block;
            }
        }
        
        publicKeySuccess = YES;
        
        // authenticate using private key
        int ret = ssh_userauth_publickey(strongSelf->_rawSession, NULL, parser.privateKey);
        switch (ret) {
            case SSH_AUTH_AGAIN:
                // try again
                return;
                
            default:
                [strongSelf _checkAuthenticateResult:ret];
                return_from_block;
        }
    }};
    
    [self dispatchAsyncOnSessionQueue:_authBlock];
}

#pragma mark - SSH Main Loop

/**
 * Reads the first available bytes that become available on the channel.
 **/
- (void)_setupSocketReadSource {
    [self _cancelSocketReadSource];
    
    _socketReadSource = dispatch_source_create(DISPATCH_SOURCE_TYPE_READ, self->_connector.socketFD, 0, _sessionQueue);
    
    if (!_socketReadSource) {
        NSError *error = [[NSError alloc] initWithDomain:SSHKitCoreErrorDomain
                                                    code:SSHKitErrorFatal
                                                userInfo:@{NSLocalizedDescriptionKey : @"Could not create dispatch source to monitor socket" }];
        [self disconnectWithError:error];
        return;
    }
    
    __weak SSHKitSession *weakSelf = self;
    dispatch_source_set_event_handler(_socketReadSource, ^{ @autoreleasepool {
        __strong SSHKitSession *strongSelf = weakSelf;
        if (!strongSelf) {
            return_from_block;
        }
        
        [strongSelf _registerLogCallback];
        
        // reset keepalive counter
        strongSelf->_keepAliveCounter = strongSelf.serverAliveCountMax;
        
        switch (strongSelf->_stage) {
            case SSHKitSessionStageNotConnected:
            case SSHKitSessionStageOpeningSocket:
                break;
            case SSHKitSessionStageConnecting:
                [strongSelf _doConnect];
                break;
            case SSHKitSessionStagePreAuthenticate:
                [strongSelf _preAuthenticate];
                break;
            case SSHKitSessionStageAuthenticating:
                if (strongSelf->_authBlock) {
                    strongSelf->_authBlock();
                }
                
                break;
            case SSHKitSessionStageAuthenticated: {
                // try forward-tcpip requests
                [strongSelf doSendForwardRequest];
                
                // probe forward channel from accepted forward
                // WARN: keep following lines of code, prevent wild data trigger dispatch souce again and again
                //       another method is create a temporary channel, and let it consumes the wild data.
                //       The real cause is unkown, may be it's caused by data arrived while channels already closed
                SSHKitForwardChannel *forwardChannel = [self openForwardChannel];
                
                if (forwardChannel) {
                    if (strongSelf->_delegateFlags.didOpenForwardChannel) {
                        [strongSelf->_delegate session:strongSelf didOpenForwardChannel:forwardChannel];
                    }
                }
                
                // copy channels here, NSEnumerationReverse still not safe while removing object in array
                NSArray *channels = [strongSelf->_channels copy];
                for (SSHKitChannel *channel in channels) {
                    switch (channel.stage) {
                        case SSHKitChannelStageOpening:
                            [channel doOpen];
                            break;
                            
                        case SSHKitChannelStageReady:
                            [channel doWrite];
                            break;
                            
                        case SSHKitChannelStageClosed:
                            [strongSelf->_channels removeObject:channel];
                            break;
                            
                        default:
                            break;
                    }
                }
                
                break;
            }
                
            case SSHKitSessionStageUnknown:
            default:
                // should never comes here
                break;
        }
    }});
    
    dispatch_resume(_socketReadSource);
}

- (void)_cancelSocketReadSource {
    if (_socketReadSource) {
        dispatch_source_cancel(_socketReadSource);
        _socketReadSource = nil;
    }
}

// -----------------------------------------------------------------------------
#pragma mark - Extra Options
// -----------------------------------------------------------------------------

- (void)enableProxyWithType:(SSHKitProxyType)type host:(NSString *)host port:(uint16_t)port {
    self.proxyType = type;
    self.proxyHost = host;
    self.proxyPort = port;
}
- (void)enableProxyWithType:(SSHKitProxyType)type host:(NSString *)host port:(uint16_t)port user:(NSString *)user password:(NSString *)password {
    self.proxyType = type;
    self.proxyHost = host;
    self.proxyPort = port;
    self.proxyUsername = user;
    self.proxyPassword = password;
}

#pragma mark - Keep-alive Heartbeat

- (void)_setupKeepAliveTimer {
    if (self.serverAliveCountMax<=0) {
        return;
    }
    
    [self _cancelKeepAliveTimer];
    
    _keepAliveTimer = dispatch_source_create(DISPATCH_SOURCE_TYPE_TIMER, 0, 0, _sessionQueue);
    if (!_keepAliveTimer) {
        if (_logDebug) _logDebug(@"Failed to create keep-alive timer");
        return;
    }
    
    _keepAliveCounter = self.serverAliveCountMax;
    
    uint64_t interval = SSHKIT_SESSION_DEFAULT_TIMEOUT;
    
    if (_timeout > 0) {
        interval = _timeout;
    }
    
    dispatch_source_set_timer(_keepAliveTimer, dispatch_time(DISPATCH_TIME_NOW, interval * NSEC_PER_SEC), interval * NSEC_PER_SEC, (1ull * NSEC_PER_SEC) / 10);
    
    __weak SSHKitSession *weakSelf = self;
    dispatch_source_set_event_handler(_keepAliveTimer, ^{
        __strong SSHKitSession *strongSelf = weakSelf;
        if (!strongSelf) {
            return_from_block;
        }
        
        [strongSelf _registerLogCallback];
        
        if (strongSelf->_keepAliveCounter<=0) {
            NSString *errorDesc = [NSString stringWithFormat:@"Timeout, server %@ not responding", strongSelf.host];
            [strongSelf _doDisconnectWithError:[NSError errorWithDomain:SSHKitCoreErrorDomain
                                                                code:SSHKitErrorTimeout
                                                            userInfo:@{ NSLocalizedDescriptionKey : errorDesc } ]];
            return_from_block;
        }
        
        int result = ssh_send_keepalive(strongSelf->_rawSession);
        if (result!=SSH_OK) {
            [strongSelf _doDisconnectWithError:strongSelf.coreError];
            return;
        }
        
        strongSelf->_keepAliveCounter--;
        
        [strongSelf disconnectIfNeeded];
    });
    
    dispatch_resume(_keepAliveTimer);
}

- (void)_cancelKeepAliveTimer {
    if (_keepAliveTimer) {
        dispatch_source_cancel(_keepAliveTimer);
        _keepAliveTimer = nil;
    }
}

#pragma mark - Libssh logging

static void raw_session_log_callback(int priority, const char *function, const char *message, void *userdata) {
#ifdef DEBUG
    SSHKitSession *aSelf = (__bridge SSHKitSession *)userdata;
    
    if (aSelf) {
        switch (priority) {
            case SSH_LOG_TRACE:
            case SSH_LOG_DEBUG:
                 if (aSelf->_logDebug) aSelf->_logDebug(@"%s", message);
                break;
                
            case SSH_LOG_INFO:
                if (aSelf->_logInfo) aSelf->_logInfo(@"%s", message);
                break;
                
            case SSH_LOG_WARN:
                if (aSelf->_logWarn) aSelf->_logWarn(@"%s", message);
                break;
                
            default:
                if (aSelf->_logError) aSelf->_logError(@"%s", message);
                break;
        }
    }
#endif
}

/* WARN: GCD is thread-blind execution of threaded code, where you submit blocks of code to be run on any available system-owned thread.
 *
 * The drawback of this behavior is __thread keyword used by libssh DOES NOT work!
 * 
 * Problem: instead of use a ssh_session struct member variable, libssh presupposes ssh_ssesion and execution thread are one-to-one map, so it uses __thread keyword to store log function and userdata for a session.
 *
 * Howto fix: at the very beginning of _sessionQueue execution block of code, call [strongSelf _registerLogCallback] to make sure libssh __thread storage reinitialized properly.
 *
 * Performance affected: although call _registerLogCallback again and again might lead to performance issue, but since libssh log callback only effective on DEBUG scheme, the performance effect should be trivial while on RELEASE scheme.
 */
- (void)_registerLogCallback {
#ifdef DEBUG
    ssh_set_log_callback(raw_session_log_callback);
    ssh_set_log_userdata((__bridge void *)(self));
    ssh_set_log_level(SSH_LOG_TRACE);
#endif
}

@end
