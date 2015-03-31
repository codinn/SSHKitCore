#import "SSHKitSession.h"
#import "SSHKitCore+Protected.h"
#import <libssh/libssh.h>
#import <libssh/callbacks.h>
#import <libssh/server.h>
#import "SSHKitConnector.h"
#import "SSHKitConnector.h"
#import "SSHKitPrivateKeyParser.h"

#define SOCKET_NULL -1

typedef NS_ENUM(NSInteger, SSHKitSessionStage) {
    SSHKitSessionStageUnknown   = 0,
    SSHKitSessionStageNotConnected,
    SSHKitSessionStageOpeningSocket,
    SSHKitSessionStageConnecting,
    SSHKitSessionStagePreAuthenticate,
    SSHKitSessionStageAuthenticating,
    SSHKitSessionStageAuthenticated,
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
        unsigned int didAcceptForwardChannel        : 1;
	} _delegateFlags;
    
	dispatch_source_t   _readSource;
    dispatch_source_t   _keepAliveTimer;
    NSInteger           _keepAliveCounter;
    
    dispatch_block_t    _authBlock;
    
    void *_isOnSessionQueueKey;
    
    // make sure disconnect only once
    BOOL _alreadyDidDisconnect;
    
    SSHKitConnector     *_connector;
    
    NSMutableArray      *_forwardRequests;
    NSMutableArray      *_channels;
}

@property (nonatomic, readwrite)  SSHKitSessionStage currentStage;
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

+ (void)initialize
{
    static dispatch_once_t onceToken;
    
    dispatch_once(&onceToken, ^{
        dispatch_block_t block = ^{
            // use libssh with threads, GCD should be pthread based
            ssh_threads_set_callbacks(ssh_threads_get_pthread());
            ssh_init();
        };
        
        if ([NSThread isMainThread]) {
            block();
        } else {
            dispatch_sync(dispatch_get_main_queue(), block);
        }
    });
}

- (instancetype)init
{
	return [self initWithDelegate:nil sessionQueue:NULL];
}

- (instancetype)initWithDelegate:(id<SSHKitSessionDelegate>)aDelegate
{
	return [self initWithDelegate:aDelegate sessionQueue:NULL];
}

- (instancetype)initWithDelegate:(id<SSHKitSessionDelegate>)aDelegate sessionQueue:(dispatch_queue_t)sq
{
    if ((self = [super init])) {
        self.enableCompression = NO;
        self.enableIPv4 = YES;
        self.enableIPv6 = YES;
        
        _rawSession = ssh_new();
        
        if (!_rawSession) {
            return nil;
        }
        
        self.currentStage = SSHKitSessionStageNotConnected;
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
        
        _alreadyDidDisconnect = NO;
    }
    
    return self;
}

- (void)dealloc
{
    [self dispatchSyncOnSessionQueue: ^{
        [self _disconnectWithError:nil];
        ssh_free(self.rawSession);
        self->_rawSession = NULL;
	}];
}

-(NSString *)description
{
    return [NSString stringWithFormat:@"%@@%@:%d", self.username, self.host, self.port];
}

#pragma mark Configuration

- (void)setDelegate:(id<SSHKitSessionDelegate>)delegate
{
	if (_delegate != delegate) {
		_delegate = delegate;
        _delegateFlags.authenticateWithAllowedMethodsPartialSuccess = [delegate respondsToSelector:@selector(session:authenticateWithAllowedMethods:partialSuccess:)];
		_delegateFlags.didConnectToHostPort = [delegate respondsToSelector:@selector(session:didConnectToHost:port:)];
		_delegateFlags.didDisconnectWithError = [delegate respondsToSelector:@selector(session:didDisconnectWithError:)];
		_delegateFlags.keyboardInteractiveRequest = [delegate respondsToSelector:@selector(session:keyboardInteractiveRequest:)];
        _delegateFlags.shouldConnectWithHostKey = [delegate respondsToSelector:@selector(session:shouldConnectWithHostKey:)];
        _delegateFlags.didReceiveIssueBanner = [delegate respondsToSelector:@selector(session:didReceiveIssueBanner:)];
        _delegateFlags.didAcceptForwardChannel = [delegate respondsToSelector:@selector(session:didAcceptForwardChannel:)];
        _delegateFlags.didAuthenticateUser = [delegate respondsToSelector:@selector(session:didAuthenticateUser:)];
	}
}

// -----------------------------------------------------------------------------
#pragma mark Connecting
// -----------------------------------------------------------------------------

- (void)_doConnect
{
    int result = ssh_connect(_rawSession);
    if (self.logHandler) self.logHandler(@"SESSION DEBUG: session connecting with result: %d", result);
    
    switch (result) {
        case SSH_OK:
            // connection established
        {
            if (self.logHandler) self.logHandler(@"SESSION DEBUG: session connected");
            
            const char *clientbanner = ssh_get_clientbanner(self.rawSession);
            if (clientbanner) self.clientBanner = @(clientbanner);
            
            if (self.logHandler) self.logHandler(@"SESSION DEBUG: client banner %@", self.clientBanner);
            
            const char *serverbanner = ssh_get_serverbanner(self.rawSession);
            if (serverbanner) self.serverBanner = @(serverbanner);
            
            if (self.logHandler) self.logHandler(@"SESSION DEBUG: server banner %@", self.serverBanner);
            
            int ver = ssh_get_version(self.rawSession);
            
            if (ver>0) {
                self.protocolVersion = @(ver).stringValue;
            }
            
            if (_delegateFlags.didConnectToHostPort) {
                [self.delegate session:self didConnectToHost:self.host port:self.port];
            }
            
            // check host key
            NSError *error = nil;
            SSHKitHostKeyParser *hostKey = [SSHKitHostKeyParser parserFromSession:self error:&error];
            
            if ( !error && ! (_delegateFlags.shouldConnectWithHostKey && [self.delegate session:self shouldConnectWithHostKey:hostKey]) )
            {
                // failed
                error = [NSError errorWithDomain:SSHKitSessionErrorDomain
                                            code:SSHKitErrorCodeHostKeyError
                                        userInfo:@{ NSLocalizedDescriptionKey : @"Server host key verification failed" }];
            }
            
            if (error) {
                [self _disconnectWithError:error];
                return;
            }
            
            self.currentStage = SSHKitSessionStagePreAuthenticate;
            [self _preAuthenticate];
        }
            break;
            
        case SSH_AGAIN:
            // try again
            break;
            
        default:
        {
            const char* errorStr = ssh_get_error(self.rawSession);
            if (errorStr) {
                if (self.logHandler) self.logHandler(@"SESSION DEBUG: unknown error occurred %@", @(errorStr));
            } else {
                if (self.logHandler) self.logHandler(@"SESSION DEBUG: unknown error occurred");
            }
            
            [self _disconnectWithError:self.lastError];
        }
            break;
            
    }
}

- (void)connectToHost:(NSString *)host onPort:(uint16_t)port withUser:(NSString*)user
{
    [self connectToHost:host onPort:port viaInterface:nil withUser:(NSString*)user timeout:0.0];
}

- (void)connectToHost:(NSString *)host onPort:(uint16_t)port withUser:(NSString *)user timeout:(NSTimeInterval)timeout
{
    [self connectToHost:host onPort:port viaInterface:nil withUser:(NSString*)user timeout:timeout];
}

- (void)connectToHost:(NSString *)host onPort:(uint16_t)port viaInterface:(NSString *)interface withUser:(NSString*)user timeout:(NSTimeInterval)timeout
{
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
        
        if (!strongSelf->_connector) {
            if (strongSelf.proxyType > SSHKitProxyTypeDirect) {
                // connect over a proxy server
                
                if (strongSelf.logHandler) strongSelf.logHandler(@"SESSION DEBUG: Connecting through proxy with type %d", strongSelf.proxyType);
                
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
                if (strongSelf.logHandler) strongSelf.logHandler(@"SESSION DEBUG: Connecting directly");
                // connect directly
                strongSelf->_connector = [[SSHKitConnector alloc] init];
            }
            
            // configure ipv4/ipv6
            strongSelf->_connector.IPv4Enabled = strongSelf.enableIPv4;
            strongSelf->_connector.IPv6Enabled = strongSelf.enableIPv6;
            
            if (strongSelf.logHandler) {
                strongSelf->_connector.logHandler = strongSelf.logHandler;
            }
            
            strongSelf.currentStage = SSHKitSessionStageOpeningSocket;
            
            NSError *error = nil;
            BOOL ret = [strongSelf->_connector connectToHost:host onPort:port viaInterface:interface withTimeout:strongSelf.timeout error:&error];
            
            if (ret) {
                if (strongSelf.logHandler) strongSelf.logHandler(@"SESSION DEBUG: socket established successfully");
            } else {
                if (strongSelf.logHandler) strongSelf.logHandler(@"SESSION DEBUG: failed to establish socket");
            }
            
            if (error) {
                [strongSelf _disconnectWithError:error];
                if (strongSelf.logHandler) strongSelf.logHandler(@"SESSION DEBUG: error: %@", error);
                return_from_block;
            }
        }
        
        int socket = strongSelf->_connector.socketFD;
        ssh_options_set(strongSelf.rawSession, SSH_OPTIONS_FD, &socket);
        
        // set socket to blocking mode
        fcntl(socket, F_SETFL, 0);
        
        // compression
        
        if (strongSelf.enableCompression) {
            ssh_options_set(strongSelf.rawSession, SSH_OPTIONS_COMPRESSION, "yes");
        } else {
            ssh_options_set(strongSelf.rawSession, SSH_OPTIONS_COMPRESSION, "no");
        }
        
        // ciphers
        if (strongSelf.ciphers.length) {
            ssh_options_set(strongSelf.rawSession, SSH_OPTIONS_CIPHERS_C_S, strongSelf.ciphers.UTF8String);
            ssh_options_set(strongSelf.rawSession, SSH_OPTIONS_CIPHERS_S_C, strongSelf.ciphers.UTF8String);
        }
        
        // host key algorithms
        if (strongSelf.keyExchangeAlgorithms.length) {
            ssh_options_set(strongSelf.rawSession, SSH_OPTIONS_KEY_EXCHANGE, strongSelf.keyExchangeAlgorithms.UTF8String);
        }
        
        // host key algorithms
        if (strongSelf.hostKeyAlgorithms.length) {
            ssh_options_set(strongSelf.rawSession, SSH_OPTIONS_HOSTKEYS, strongSelf.hostKeyAlgorithms.UTF8String);
        }
        
        // tcp keepalive
        if ( strongSelf.serverAliveCountMax<=0 ) {
            int on = 1;
            if (strongSelf.logHandler) strongSelf.logHandler(@"SESSION DEBUG: enable keepalive");
            setsockopt(socket, SOL_SOCKET, SO_KEEPALIVE, (void *)&on, sizeof(on));
        }
        
        ssh_options_set(strongSelf.rawSession, SSH_OPTIONS_USER, strongSelf.username.UTF8String);
#if DEBUG
        int verbosity = SSH_LOG_FUNCTIONS;
#else
        int verbosity = SSH_LOG_NOLOG;
#endif
        ssh_options_set(strongSelf.rawSession, SSH_OPTIONS_LOG_VERBOSITY, &verbosity);
        
        if (strongSelf->_timeout > 0) {
            ssh_options_set(strongSelf.rawSession, SSH_OPTIONS_TIMEOUT, &strongSelf->_timeout);
        }
        
        // set to non-blocking mode
        ssh_set_blocking(strongSelf.rawSession, 0);
        if (strongSelf.logHandler) strongSelf.logHandler(@"SESSION DEBUG: set to non-blocking mode");
        
        // disconnect if connected
        if (strongSelf.isConnected) {
            [strongSelf _disconnectWithError:nil];
        }
        
        strongSelf.currentStage = SSHKitSessionStageConnecting;
        [strongSelf _startReadSource];
        [strongSelf _doConnect];
    }}];
}

- (void)dispatchSyncOnSessionQueue:(dispatch_block_t)block
{
    if (dispatch_get_specific(_isOnSessionQueueKey))
        block();
    else
        dispatch_sync(_sessionQueue, block);
}
- (void)dispatchAsyncOnSessionQueue:(dispatch_block_t)block
{
    dispatch_async(_sessionQueue, block);
}

// -----------------------------------------------------------------------------
#pragma mark Disconnecting
// -----------------------------------------------------------------------------

- (BOOL)isConnected
{
    __block BOOL flag = NO;
    
    [self dispatchSyncOnSessionQueue: ^{ @autoreleasepool {
        int status = ssh_get_status(self.rawSession);
        
        if ( (status & SSH_CLOSED_ERROR) || (status & SSH_CLOSED) || (ssh_is_connected(self.rawSession) == 0) ) {
            flag = NO;
        } else {
            flag = YES;
        }
    }}];
    
    return flag;
}

- (void)disconnect
{
    // Asynchronous disconnection
    
    @synchronized(self) {    // lock
        [self _invalidateKeepAliveTimer];
        
        if (!_alreadyDidDisconnect) { // not run yet?
            // do stuff once
            _alreadyDidDisconnect = YES;
            
            __weak SSHKitSession *weakSelf = self;
            // Synchronous disconnection, as documented in the header file
            [self dispatchAsyncOnSessionQueue: ^{ @autoreleasepool {
                __strong SSHKitSession *strongSelf = weakSelf;
                if (!strongSelf) {
                    return_from_block;
                }
                
                [strongSelf _doDisconnectWithError:nil];
            }}];
        }
    }
}

- (void)impoliteDisconnect
{
    if (_connector) {
        [_connector disconnect];
    }
    
    [self disconnect];
}

- (void)_doDisconnectWithError:(NSError *)error
{
    if (_readSource) {
        dispatch_source_cancel(_readSource);
        _readSource = nil;
    }
    
    for (SSHKitChannel* channel in _channels) {
        [channel close];
    }
    
    [_channels removeAllObjects];
    
    if (self.isConnected) {
        ssh_disconnect(_rawSession);
    }
    
    if (_connector) {
        [_connector disconnect];
    }
    
    if (_delegateFlags.didDisconnectWithError) {
        [self.delegate session:self didDisconnectWithError:error];
    }
}

- (void)_disconnectWithError:(NSError *)error
{
    // Synchronous disconnection, as documented in the header file
    
    @synchronized(self) {    // lock
        [self _invalidateKeepAliveTimer];
        
        if (!_alreadyDidDisconnect) { // not run yet?
            // do stuff once
            _alreadyDidDisconnect = YES;
            
            // Synchronous disconnection, as documented in the header file
            [self dispatchSyncOnSessionQueue: ^{ @autoreleasepool {
                [self _doDisconnectWithError:error];
            }}];
        }
    }
}

#pragma mark Diagnostics

- (NSString *)hostIP
{
    if (self.proxyHost.length) { // connect over a proxy
        return nil;
    }
    
    // _connector will be nil if use a custom socket fd
    return _connector.connectedHost;
}

- (NSError *)lastError
{
    if(!_rawSession) {
        return nil;
    }
    
    __block NSError *error;
    
    __weak SSHKitSession *weakSelf = self;
    [self dispatchSyncOnSessionQueue :^{ @autoreleasepool {
        __strong SSHKitSession *strongSelf = weakSelf;
        
        SSHKitErrorCode code = SSHKitErrorCodeNoError;
        int errorCode = ssh_get_error_code(strongSelf.rawSession);
        
        // convert to SSHKit error code
        switch (errorCode) {
            case SSH_NO_ERROR:
                return;
                
            case SSH_AUTH_DENIED:
                code = SSHKitErrorCodeAuthError;
                break;
                
            default:
                code = SSHKitErrorCodeRetry;
                break;
        }
        
        const char* errorStr = ssh_get_error(strongSelf.rawSession);
        if (!errorStr) {
            error = [NSError errorWithDomain:SSHKitLibsshErrorDomain
                                       code:SSHKitErrorCodeFatal
                                   userInfo:nil];
        }
        
        error = [NSError errorWithDomain:SSHKitLibsshErrorDomain
                                   code:code
                               userInfo:@{ NSLocalizedDescriptionKey : @(errorStr) }];
    }}];
    
    return error;
}

// -----------------------------------------------------------------------------
#pragma mark Authentication
// -----------------------------------------------------------------------------

- (NSArray *)_getUserAuthList
{
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

- (void)_preAuthenticate
{
    // must call this method before next auth method, or libssh will be failed
    int rc = ssh_userauth_none(_rawSession, NULL);
    
    switch (rc) {
        case SSH_AUTH_AGAIN:
            // try again
            break;
            
        case SSH_AUTH_DENIED:
        {
            // pre auth success
            
            if (_delegateFlags.didAcceptForwardChannel) {
                /*
                 *** Does not work without calling ssh_userauth_none() first ***
                 *** That will be fixed ***
                 */
                const char *banner = ssh_get_issue_banner(self.rawSession);
                if (banner) [self.delegate session:self didReceiveIssueBanner:@(banner)];
            }
            
            NSArray *authMethods = [self _getUserAuthList];
            
            if (_delegateFlags.authenticateWithAllowedMethodsPartialSuccess) {
                NSError *error = [self.delegate session:self authenticateWithAllowedMethods:authMethods partialSuccess:NO];
                if (error) {
                    [self _disconnectWithError:error];
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

- (void)_didAuthenticate
{
    // start diagnoses timer
    [self _fireKeepAliveTimer];
    
    self.currentStage = SSHKitSessionStageAuthenticated;
    
    if (_delegateFlags.didAuthenticateUser) {
        [self.delegate session:self didAuthenticateUser:nil];
    }
}

- (void)_checkAuthenticateResult:(NSInteger)result
{
    switch (result) {
        case SSH_AUTH_DENIED:
            [self _disconnectWithError:self.lastError];
            return;
            
        case SSH_AUTH_ERROR:
            [self _disconnectWithError:self.lastError];
            return;
            
        case SSH_AUTH_SUCCESS:
            [self _didAuthenticate];
            return;
            
        case SSH_AUTH_PARTIAL:
        {
            // pre auth success
            NSArray *authMethods = [self _getUserAuthList];
            
            if (_delegateFlags.authenticateWithAllowedMethodsPartialSuccess) {
                NSError *error = [self.delegate session:self authenticateWithAllowedMethods:authMethods partialSuccess:YES];
                if (error) {
                    [self _disconnectWithError:error];
                }
                
                // Handoff to next auth method
                return;
            }
        }
            return;
            
        case SSH_AUTH_AGAIN: // should never come here
        default:
            [self _disconnectWithError:[NSError errorWithDomain:SSHKitSessionErrorDomain
                                                          code:SSHKitErrorCodeAuthError
                                                      userInfo:@{ NSLocalizedDescriptionKey : @"Unknown error while authenticate user"} ]];
            return;
    }
}


- (void)authenticateByInteractiveHandler:(NSArray *(^)(NSInteger, NSString *, NSString *, NSArray *))interactiveHandler
{
    self.currentStage = SSHKitSessionStageAuthenticating;

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
            rc = ssh_userauth_kbdint(strongSelf.rawSession, NULL, NULL);
        }
        
        switch (rc) {
            case SSH_AUTH_AGAIN:
                // try again
                return_from_block;
                
            case SSH_AUTH_INFO:
            {
                const char* name = ssh_userauth_kbdint_getname(strongSelf.rawSession);
                NSString *nameString = name ? @(name) : nil;
                
                const char* instruction = ssh_userauth_kbdint_getinstruction(strongSelf.rawSession);
                NSString *instructionString = instruction ? @(instruction) : nil;
                
                int nprompts = ssh_userauth_kbdint_getnprompts(strongSelf.rawSession);
                
                if (nprompts>0) { // getnprompts may return zero
                    NSMutableArray *prompts = [@[] mutableCopy];
                    for (int i = 0; i < nprompts; i++) {
                        char echo = NO;
                        const char *prompt = ssh_userauth_kbdint_getprompt(strongSelf.rawSession, i, &echo);
                        
                        NSString *promptString = prompt ? @(prompt) : @"";
                        [prompts addObject:@[promptString, @(echo)]];
                    }
                    
                    NSArray *information = interactiveHandler(index, nameString, instructionString, prompts);
                    
                    for (int i = 0; i < information.count; i++) {
                        if (ssh_userauth_kbdint_setanswer(strongSelf.rawSession, i, [information[i] UTF8String]) < 0)
                        {
                            // failed
                            break;
                        }
                    }
                }
                
                index ++;
            }
                // send and check again
                rc = ssh_userauth_kbdint(strongSelf.rawSession, NULL, NULL);
                return_from_block;
                
            default:
                break;
        }
        
        [strongSelf _checkAuthenticateResult:rc];
    }};
    
    [self dispatchAsyncOnSessionQueue:_authBlock];
}

- (void)authenticateByPasswordHandler:(NSString *(^)(void))passwordHandler;
{
    NSString *password = passwordHandler();
    
    self.currentStage = SSHKitSessionStageAuthenticating;
    
    __weak SSHKitSession *weakSelf = self;
    _authBlock = ^{ @autoreleasepool {
        __strong SSHKitSession *strongSelf = weakSelf;
        if (!strongSelf) {
            return_from_block;
        }
        
        // try "password" method, which is deprecated in SSH 2.0
        int rc = ssh_userauth_password(strongSelf.rawSession, NULL, password.UTF8String);
        
        if (rc == SSH_AUTH_AGAIN) {
            // try again
            return;
        }
        
        [strongSelf _checkAuthenticateResult:rc];
    }};
    
    [self dispatchAsyncOnSessionQueue: _authBlock];
}

- (void)authenticateByPrivateKeyParser:(SSHKitPrivateKeyParser *)parser
{
    self.currentStage = SSHKitSessionStageAuthenticating;
    
    __block BOOL publicKeySuccess = NO;
    __weak SSHKitSession *weakSelf = self;
    
    _authBlock = ^{ @autoreleasepool {
        __strong SSHKitSession *strongSelf = weakSelf;
        if (!strongSelf) {
            return_from_block;
        }
        
        if (!publicKeySuccess) {
            // try public key
            int ret = ssh_userauth_try_publickey(strongSelf.rawSession, NULL, parser.publicKey);
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
        int ret = ssh_userauth_publickey(strongSelf.rawSession, NULL, parser.privateKey);
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

// -----------------------------------------------------------------------------
#pragma mark - CALLBACKS
// -----------------------------------------------------------------------------

- (void)_doReadWrite
{
    if (!self.isConnected) {
        [self _disconnectWithError:self.lastError];
    }
    
    // iterate channels, use NSEnumerationReverse to safe remove object in array
    [_channels enumerateObjectsWithOptions:NSEnumerationReverse usingBlock:^(SSHKitChannel *channel, NSUInteger index, BOOL *stop)
    {
        switch (channel.stage) {
            case SSHKitChannelStageOpening1:
                switch (channel.type) {
                    case SSHKitChannelTypeDirect:
                        [channel _doOpenDirect];
                        break;
                        
                    case SSHKitChannelTypeShell:
                        [channel _doOpenSession];
                        break;
                        
                    default:
                        break;
                }
                break;
                
            case SSHKitChannelStageOpening2:
                switch (channel.type) {
                    case SSHKitChannelTypeShell:
                        [channel _doRequestPty];
                        break;
                        
                    default:
                        break;
                }
                break;
                
                
            case SSHKitChannelStageOpening3:
                switch (channel.type) {
                    case SSHKitChannelTypeShell:
                        [channel _doRequestShell];
                        break;
                        
                    default:
                        break;
                }
                break;
                
            case SSHKitChannelStageClosed:
                [self removeChannel:channel];
                break;
                
            case SSHKitChannelStageReadWrite:
                [channel _doRead];
                break;
                
            default:
                break;
        }
    }];
    
    // try again forward-tcpip requests
    [_forwardRequests enumerateObjectsWithOptions:NSEnumerationReverse usingBlock:^(NSArray *forwardRequest, NSUInteger index, BOOL *stop) {
        NSString *safeHost = forwardRequest[0];
        if ([safeHost isEqual:[NSNull null]]) {
            safeHost = NULL;
        }
        
        [SSHKitChannel _doRequestRemoteForwardOnSession:self withListenHost:safeHost listenPort:[forwardRequest[1] unsignedShortValue] completionHandler:forwardRequest[2]];
    }];
    
    // probe forward channel from accepted forward
    // WARN: keep following lines of code, prevent wild data trigger dispatch souce again and again
    //       another method is create a temporary channel, and let it consumes the wild data.
    //       The real cause is unkown, may be it's caused by data arrived while channels already closed
    SSHKitChannel *forwardChannel = [SSHKitChannel _tryCreateForwardChannelFromSession:self];
    
    if (forwardChannel) {
        if (_delegateFlags.didAcceptForwardChannel) {
            [_delegate session:self didAcceptForwardChannel:forwardChannel];
        }
    }
}

/**
 * Reads the first available bytes that become available on the channel.
 **/
- (void)_startReadSource
{
    if (_readSource) {
        dispatch_source_cancel(_readSource);
    }
    
    _readSource = dispatch_source_create(DISPATCH_SOURCE_TYPE_READ, self->_connector.socketFD, 0, _sessionQueue);
    
    __weak SSHKitSession *weakSelf = self;
    dispatch_source_set_event_handler(_readSource, ^{ @autoreleasepool {
        __strong SSHKitSession *strongSelf = weakSelf;
        if (!strongSelf) {
            return_from_block;
        }
        
        // reset keepalive counter
        strongSelf->_keepAliveCounter = strongSelf.serverAliveCountMax;
        
        switch (strongSelf.currentStage) {
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
            case SSHKitSessionStageAuthenticated:
                [strongSelf _doReadWrite];
                break;
            case SSHKitSessionStageUnknown:
                // should never comes to here
                break;
        }
    }});
    
    dispatch_resume(_readSource);
}

// -----------------------------------------------------------------------------
#pragma mark - Extra Options
// -----------------------------------------------------------------------------

- (void)enableProxyWithType:(SSHKitProxyType)type host:(NSString *)host port:(uint16_t)port
{
    self.proxyType = type;
    self.proxyHost = host;
    self.proxyPort = port;
}
- (void)enableProxyWithType:(SSHKitProxyType)type host:(NSString *)host port:(uint16_t)port user:(NSString *)user password:(NSString *)password
{
    self.proxyType = type;
    self.proxyHost = host;
    self.proxyPort = port;
    self.proxyUsername = user;
    self.proxyPassword = password;
}

#pragma mark - Internal Helpers

- (void)_fireKeepAliveTimer
{
    if (self.serverAliveCountMax<=0) {
        return;
    }
    
    _keepAliveTimer = dispatch_source_create(DISPATCH_SOURCE_TYPE_TIMER, 0, 0, _sessionQueue);
    _keepAliveCounter = self.serverAliveCountMax;
    
    uint64_t interval = SSHKit_SESSION_DEFAULT_TIMEOUT;
    
    if (_timeout > 0) {
        interval = _timeout;
    }
    
    if (_keepAliveTimer)
    {
        dispatch_source_set_timer(_keepAliveTimer, dispatch_time(DISPATCH_TIME_NOW, interval * NSEC_PER_SEC), interval * NSEC_PER_SEC, (1ull * NSEC_PER_SEC) / 10);
        
        __weak SSHKitSession *weakSelf = self;
        dispatch_source_set_event_handler(_keepAliveTimer, ^{
            __strong SSHKitSession *strongSelf = weakSelf;
            if (!strongSelf) {
                return_from_block;
            }
            
            if (strongSelf->_keepAliveCounter<=0) {
                NSString *errorDesc = [NSString stringWithFormat:@"Timeout, server %@ not responding", strongSelf.host];
                [strongSelf _disconnectWithError:[NSError errorWithDomain:SSHKitSessionErrorDomain
                                                                    code:SSHKitErrorCodeTimeout
                                                                userInfo:@{ NSLocalizedDescriptionKey : errorDesc } ]];
                return_from_block;
            }
            
            int result = ssh_send_keepalive(strongSelf->_rawSession);
            if (result!=SSH_OK) {
                [strongSelf _disconnectWithError:strongSelf.lastError];
                return;
            }
            
            if (!strongSelf.isConnected) {
                [strongSelf _disconnectWithError:strongSelf.lastError];
                return;
            }
            
            strongSelf->_keepAliveCounter--;
        });
        
        dispatch_resume(_keepAliveTimer);
    }
}

- (void)_invalidateKeepAliveTimer
{
    if (_keepAliveTimer) {
        dispatch_source_cancel(_keepAliveTimer);
        _keepAliveTimer = nil;
    }
}

#pragma mark - Enqueue / Dequeue Request and Channel

- (void)addChannel:(SSHKitChannel *)channel
{
    [_channels addObject:channel];
}
- (void)removeChannel:(SSHKitChannel *)channel
{
    [_channels removeObject:channel];
}

- (void)addForwardRequest:(NSArray *)forwardRequest
{
    if (NSNotFound == [_forwardRequests indexOfObject:forwardRequest]) {
        [_forwardRequests addObject:forwardRequest];
    }
}
- (void)removeForwardRequest:(NSArray *)forwardRequest
{
    [_forwardRequests removeObject:forwardRequest];
}

@end
