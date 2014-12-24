#import "SSHKitSession.h"
#import "SSHKit+Protected.h"
#import <libssh/libssh.h>
#import <libssh/callbacks.h>
#import <libssh/server.h>
#import "SSHKitConnector.h"
#import "SSHKitConnectorProxy.h"
#import "SSHKitIdentityParser.h"

@interface SSHKitSession () {
	struct {
		unsigned int keyboardInteractiveRequest     : 1;
		unsigned int didConnectToHostPort           : 1;
		unsigned int didDisconnectWithError         : 1;
		unsigned int shouldConnectWithHostKey       : 1;
		unsigned int didAuthenticateUser            : 1;
        unsigned int needAuthenticateUser           : 1;
        unsigned int didAcceptForwardChannel        : 1;
	} _delegateFlags;
    
	dispatch_source_t _readSource;
    dispatch_source_t _keepAliveTimer;
    NSInteger _keepAliveCounter;
    NSMutableArray *_channels;
    NSMutableArray *_forwardRequests;
    NSMutableArray *_acceptedForwards;
    
    dispatch_block_t    _authBlock;
    
    void *_isOnSessionQueueKey;
    
    // make sure disconnect only once
    BOOL _alreadyDidDisconnect;
    
    int _customSocketFD;
    
    SSHKitConnector *_connector;
}

@property (nonatomic, readwrite)  SSHKitSessionStage currentStage;
@property (nonatomic, readwrite)  NSString    *host;
@property (nonatomic, readwrite)  NSString    *hostIP;
@property (nonatomic, readwrite)  uint16_t    port;
@property (nonatomic, readwrite)  NSString    *username;
@property (nonatomic, readwrite)  NSString    *privateKeyPath;

@property (nonatomic, readwrite)  NSString    *clientBanner;
@property (nonatomic, readwrite)  NSString    *issueBanner;
@property (nonatomic, readwrite)  NSString    *serverBanner;
@property (nonatomic, readwrite)  NSString    *protocolVersion;

@property (nonatomic, readonly) long          timeout;

@property (nonatomic, readwrite) NSInteger authMethods;

@property (atomic, readwrite) dispatch_queue_t sessionQueue;
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
	return [self initWithDelegate:nil sessionQueue:NULL socketFD:0];
}

- (instancetype)initWithDelegate:(id<SSHKitSessionDelegate>)aDelegate
{
	return [self initWithDelegate:aDelegate sessionQueue:NULL socketFD:0];
}

- (instancetype)initWithDelegate:(id<SSHKitSessionDelegate>)aDelegate socketFD:(int)socketFD
{
    return [self initWithDelegate:aDelegate sessionQueue:NULL socketFD:socketFD];
}

- (instancetype)initWithDelegate:(id<SSHKitSessionDelegate>)aDelegate sessionQueue:(dispatch_queue_t)sq
{
    return [self initWithDelegate:aDelegate sessionQueue:sq socketFD:0];
}

- (instancetype)initWithDelegate:(id<SSHKitSessionDelegate>)aDelegate sessionQueue:(dispatch_queue_t)sq socketFD:(int)socketFD
{
    if ((self = [super init])) {
        _rawSession = ssh_new();
        
        if (!_rawSession) {
            return nil;
        }
        
        self.currentStage = SSHKitSessionStageNotConnected;
        _channels = [@[] mutableCopy];
        _forwardRequests = [@[] mutableCopy];
        _acceptedForwards = [@[] mutableCopy];
        _customSocketFD = socketFD;
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
        [self disconnect];
        ssh_free(self->_rawSession);
        self->_rawSession= NULL;
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
        _delegateFlags.needAuthenticateUser = [delegate respondsToSelector:@selector(session:needAuthenticateUser:)];
		_delegateFlags.didConnectToHostPort = [delegate respondsToSelector:@selector(session:didConnectToHost:port:)];
		_delegateFlags.didDisconnectWithError = [delegate respondsToSelector:@selector(session:didDisconnectWithError:)];
		_delegateFlags.keyboardInteractiveRequest = [delegate respondsToSelector:@selector(session:keyboardInteractiveRequest:)];
        _delegateFlags.shouldConnectWithHostKey = [delegate respondsToSelector:@selector(session:shouldConnectWithHostKey:)];
	}
}

// -----------------------------------------------------------------------------
#pragma mark Connecting
// -----------------------------------------------------------------------------

- (void)_doConnect
{
    int result = ssh_connect(_rawSession);
    
    switch (result) {
        case SSH_OK:
            // connection established
        {
            const char *clientbanner = ssh_get_clientbanner(self.rawSession);
            if (clientbanner) self.clientBanner = @(clientbanner);
            
            const char *serverbanner = ssh_get_serverbanner(self.rawSession);
            if (serverbanner) self.serverBanner = @(serverbanner);
            
            int ver = ssh_get_version(self.rawSession);
            
            if (ver>0) {
                self.protocolVersion = @(ver).stringValue;
            }
            
            [self _resolveHostIP];
            
            // check host key
            SSHKitHostKeyParser *hostKey = [[SSHKitHostKeyParser alloc] init];
            NSError *error = [hostKey parseFromSession:self];
            
            if ( !error && ! (_delegateFlags.shouldConnectWithHostKey && [self.delegate session:self shouldConnectWithHostKey:hostKey]) )
            {
                // failed
                error = [NSError errorWithDomain:SSHKitSessionErrorDomain
                                            code:SSHKitErrorCodeHostKeyError
                                        userInfo:@{ NSLocalizedDescriptionKey : @"Server host key verification failed" }];
            }
            
            if (error) {
                [self disconnectWithError:error];
                return;
            }
            
            self.currentStage = SSHKitSessionStagePreAuthenticating;
            [self _preAuthenticate];
        }
            break;
            
        case SSH_AGAIN:
            // try again
            break;
            
        default:
            [self disconnectWithError:self.lastError];
            break;
            
    }
}

- (void)connectToHost:(NSString *)host onPort:(uint16_t)port withUser:(NSString*)user
{
    [self connectToHost:host onPort:port withUser:(NSString*)user timeout:0.0];
}

- (void)connectToHost:(NSString *)host onPort:(uint16_t)port withUser:(NSString *)user timeout:(NSTimeInterval)timeout
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
        
        // set to non-blocking mode
        ssh_set_blocking(strongSelf.rawSession, 0);
        
        if (strongSelf->_customSocketFD) {
            // libssh will close this fd automatically
            ssh_options_set(strongSelf.rawSession, SSH_OPTIONS_FD, &strongSelf->_customSocketFD);
        } else {
            if (self.proxyType > SSHKitProxyTypeDirect) {
                // connect over a proxy server
                
                id ConnectProxyClass = SSHKitConnectorProxy.class;
                
                switch (self.proxyType) {
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
                    strongSelf->_connector = [[ConnectProxyClass alloc] initWithProxy:strongSelf.proxyHost onPort:strongSelf.proxyPort username:strongSelf.proxyUsername password:strongSelf.proxyPassword timeout:timeout];
                } else {
                    strongSelf->_connector = [[ConnectProxyClass alloc] initWithProxy:strongSelf.proxyHost onPort:strongSelf.proxyPort timeout:strongSelf.timeout];
                }
            } else {
                // connect directly
                strongSelf->_connector = [[SSHKitConnector alloc] initWithTimeout:timeout];
            }
            
            NSError *error = nil;
            [strongSelf->_connector connectToTarget:host onPort:port error:&error];
            
            if (error) {
                [strongSelf disconnectWithError:error];
                return;
            }
            
            socket_t socket_fd = [strongSelf->_connector dupSocketFD];
            ssh_options_set(strongSelf.rawSession, SSH_OPTIONS_FD, &socket_fd);
        }
        
        ssh_options_set(strongSelf.rawSession, SSH_OPTIONS_USER, strongSelf.username.UTF8String);
#if DEBUG
        int verbosity = SSH_LOG_FUNCTIONS;
#else
        int verbosity = SSH_LOG_NOLOG;
#endif
        ssh_options_set(strongSelf.rawSession, SSH_OPTIONS_LOG_VERBOSITY, &verbosity);
        ssh_options_set(strongSelf.rawSession, SSH_OPTIONS_HOSTKEYS,
                        "ssh-rsa,ssh-dss,"
                        "ecdsa-sha2-nistp256-cert-v01@openssh.com,"
                        "ecdsa-sha2-nistp384-cert-v01@openssh.com,"
                        "ecdsa-sha2-nistp521-cert-v01@openssh.com,"
                        "ssh-rsa-cert-v01@openssh.com,ssh-dss-cert-v01@openssh.com,"
                        "ssh-rsa-cert-v00@openssh.com,ssh-dss-cert-v00@openssh.com,"
                        "ecdsa-sha2-nistp256,ecdsa-sha2-nistp384,ecdsa-sha2-nistp521"
                        );
        
        if (strongSelf->_timeout > 0) {
            ssh_options_set(strongSelf.rawSession, SSH_OPTIONS_TIMEOUT, &strongSelf->_timeout);
        }
        
        // disconnect if connected
        if (strongSelf.isConnected) {
            [strongSelf disconnect];
        }
        
        strongSelf.currentStage = SSHKitSessionStageConnecting;
        [strongSelf _doConnect];
        [strongSelf _startSessionLoop];
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
    __weak SSHKitSession *weakSelf = self;
    
    [self dispatchSyncOnSessionQueue: ^{ @autoreleasepool {
        __strong SSHKitSession *strongSelf = weakSelf;
        int status = ssh_get_status(strongSelf->_rawSession);
        
        if ( (status & SSH_CLOSED_ERROR) || (status & SSH_CLOSED) || (ssh_is_connected(strongSelf->_rawSession) == 0) ) {
            flag = NO;
        } else {
            flag = YES;
        }
    }}];
    
    return flag;
}

- (void)disconnect
{
	// Synchronous disconnection, as documented in the header file
    [self disconnectWithError:nil];
}

- (void)disconnectAsync
{
    @synchronized(self) {    // lock
        [self _invalidateKeepAliveTimer];
        
        if (!_alreadyDidDisconnect) { // not run yet?
            // do stuff once
            _alreadyDidDisconnect = YES;
            
            // Synchronous disconnection, as documented in the header file
            [self dispatchAsyncOnSessionQueue: ^{ @autoreleasepool {
                [self _doDisconnectWithError:nil];
            }}];
        }
    }
}

- (void)_doDisconnectWithError:(NSError *)error
{
    if (_readSource) {
        dispatch_source_cancel(_readSource);
        _readSource = nil;
    }
    
    NSArray *channels = [_channels copy];
    
    for (SSHKitChannel* channel in channels) {
        [channel close];
    }
    
    if (self.isConnected) {
        ssh_disconnect(_rawSession);
    }
    
    if (_delegateFlags.didDisconnectWithError) {
        [self.delegate session:self didDisconnectWithError:error];
    }
}

- (void)disconnectWithError:(NSError *)error
{
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

- (void)_preAuthenticate
{
    // must call this method before next auth method, or libssh will be failed
    int rc = ssh_userauth_none(_rawSession, NULL);
    
    /*
     *** Does not work without calling ssh_userauth_none() first ***
     *** That will be fixed ***
     */
    const char *banner = ssh_get_issue_banner(self.rawSession);
    if (banner) self.issueBanner = @(banner);
    
    switch (rc) {
        case SSH_AUTH_AGAIN:
            // try again
            break;
            
        case SSH_AUTH_DENIED:
            // pre auth success
            
            self.authMethods = ssh_userauth_list(_rawSession, NULL);
            
            if (_delegateFlags.needAuthenticateUser) {
                [self.delegate session:self needAuthenticateUser:nil];
                
                // Handoff to next auth method
                return;
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
    
    self.currentStage = SSHKitSessionStageConnected;
    
    if (_delegateFlags.didConnectToHostPort) {
        [self.delegate session:self didConnectToHost:self.host port:self.port];
    }
}

- (BOOL)_checkAuthenticateResult:(NSInteger)result
{
    switch (result) {
        case SSH_AUTH_DENIED:
            [self disconnectWithError:self.lastError];
            return NO;
            
        case SSH_AUTH_ERROR:
            [self disconnectWithError:self.lastError];
            return NO;
        case SSH_AUTH_AGAIN: // actually, its timed out
            [self disconnectWithError:[NSError errorWithDomain:SSHKitSessionErrorDomain
                                                          code:SSHKitErrorCodeTimeout
                                                      userInfo:@{ NSLocalizedDescriptionKey : @"Timeout, server not responding"} ]];
            return NO;
            
            
        case SSH_AUTH_SUCCESS:
            [self _didAuthenticate];
            return YES;
            
        case SSH_AUTH_PARTIAL:
            [self disconnectWithError:[NSError errorWithDomain:SSHKitSessionErrorDomain
                                                          code:SSHKitErrorCodeAuthError
                                                      userInfo:@{ NSLocalizedDescriptionKey : @"Multifactor authentication is not supported currently."} ]];
            return NO;
            
        default:
            [self disconnectWithError:[NSError errorWithDomain:SSHKitSessionErrorDomain
                                                          code:SSHKitErrorCodeAuthError
                                                      userInfo:@{ NSLocalizedDescriptionKey : @"Unknown error while authenticate user"} ]];
            return NO;
    }
}


- (void)authenticateByInteractiveHandler:(NSArray *(^)(NSInteger, NSString *, NSString *, NSArray *))interactiveHandler
{
    if ( !(self.authMethods & SSHKitSessionUserAuthInteractive) )
    {
        NSError *error = [NSError errorWithDomain:SSHKitSessionErrorDomain
                                             code:SSHKitErrorCodeAuthError
                                         userInfo:@{ NSLocalizedDescriptionKey : @"Keyboard-Interactive authentication method is not supported by SSH server" }];
        [self disconnectWithError:error];
        return;
    }
    
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
    if ( !(self.authMethods & SSHKitSessionUserAuthPassword) ) {
        NSError *error = [NSError errorWithDomain:SSHKitSessionErrorDomain
                                             code:SSHKitErrorCodeAuthError
                                         userInfo:@{ NSLocalizedDescriptionKey : @"Password authentication method is not supported by SSH server" }];
        [self disconnectWithError:error];
        return;
    }
    
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

- (void)authenticateByPrivateKey:(NSString *)privateKeyPath passphraseHandler:(SSHKitAskPassphrasePrivateKeyBlock)handler
{
    if ( !(self.authMethods & SSHKitSessionUserAuthPublickey) ) {
        NSError *error = [NSError errorWithDomain:SSHKitSessionErrorDomain
                                    code:SSHKitErrorCodeAuthError
                                userInfo:@{ NSLocalizedDescriptionKey : @"Publickey auth method is not supported by SSH server" }];
        [self disconnectWithError:error];
        return;
    }
    
    SSHKitIdentityParser *identity = [[SSHKitIdentityParser alloc] initWithIdentityPath:privateKeyPath passphraseHandler:handler];
    
    NSError *error = [identity parse];
    
    if (error) {
        [self disconnectWithError:error];
        return;
    }
    
    self.privateKeyPath = privateKeyPath;
    
    __block BOOL publicKeySuccess = NO;
    __weak SSHKitSession *weakSelf = self;
    
    _authBlock = ^{ @autoreleasepool {
        __strong SSHKitSession *strongSelf = weakSelf;
        if (!strongSelf) {
            return_from_block;
        }
        
        if (!publicKeySuccess) {
            // try public key
            int ret = ssh_userauth_try_publickey(strongSelf.rawSession, NULL, identity.publicKey);
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
        int ret = ssh_userauth_publickey(strongSelf.rawSession, NULL, identity.privateKey);
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
    _keepAliveCounter = 3;
    
    if (!self.isConnected) {
        [self disconnectWithError:self.lastError];
    }
    
    if (self.channels.count) {
        NSArray *channels = [self.channels copy];
        
        for (SSHKitChannel *channel in channels) {
            [channel _doRead];
        }
    } else {
        // prevent wild data trigger dispatch souce again and again
        char buffer[SSHKit_CHANNEL_MAX_PACKET];
        ssh_channel fakeChannel = ssh_channel_new(_rawSession);
        // check channel package
        ssh_channel_read(fakeChannel, buffer, sizeof(buffer), 0);
        ssh_channel_free(fakeChannel);
    }
    
    NSArray *forwardRequests = [_forwardRequests copy];
    // try again forward-tcpip requests
    for (NSArray *forwardRequest in forwardRequests) {
        NSString *address   = forwardRequest[0];
        int port            = [forwardRequest[1] intValue];
        SSHKitRemotePortForwardBoundBlock completionBlock = forwardRequest[2];
        
        int boundport = 0;
        
        BOOL rc = ssh_forward_listen(self.rawSession, address.UTF8String, port, &boundport);
        
        switch (rc) {
            case SSH_OK:
                [_forwardRequests removeObject:forwardRequest];
                [_acceptedForwards addObject:@[address, @(boundport)]];
                
                completionBlock(YES, boundport, nil);
                
                break;
                
            case SSH_AGAIN:
                // try again next time
                break;
                
            case SSH_ERROR:
            default:
                [_forwardRequests removeObject:forwardRequest];
                completionBlock(NO, boundport, self.lastError);
                
                break;
        }
    }
    
    // probe forward channel from accepted forward
    if (_acceptedForwards.count > 0) {
        int destination_port = 0;
        ssh_channel channel = ssh_channel_accept_forward(self.rawSession, 0, &destination_port);
        
        if (!channel) {
            return_from_block;
        }
        
        SSHKitForwardChannel *forwardChannel = [[SSHKitForwardChannel alloc] initWithSession:self rawChannel:channel destinationPort:destination_port];
        [_channels addObject:forwardChannel];
        
        if (_delegateFlags.didAcceptForwardChannel) {
            [_delegate session:self didAcceptForwardChannel:forwardChannel];
        }
    }
}

/**
 * Reads the first available bytes that become available on the channel.
 **/
- (void)_startSessionLoop
{
    if (_readSource) {
        dispatch_source_cancel(_readSource);
    }
    
    _readSource = dispatch_source_create(DISPATCH_SOURCE_TYPE_READ, self.socketFD, 0, _sessionQueue);
    
    __weak SSHKitSession *weakSelf = self;
    dispatch_source_set_event_handler(_readSource, ^{ @autoreleasepool {
        __strong SSHKitSession *strongSelf = weakSelf;
        if (!strongSelf) {
            return_from_block;
        }
        
        switch (strongSelf.currentStage) {
            case SSHKitSessionStageNotConnected:
                break;
            case SSHKitSessionStageConnecting:
                [strongSelf _doConnect];
                break;
            case SSHKitSessionStagePreAuthenticating:
                [strongSelf _preAuthenticate];
                break;
            case SSHKitSessionStageAuthenticating:
                if (strongSelf->_authBlock) {
                    strongSelf->_authBlock();
                }
                
                break;
            case SSHKitSessionStageConnected:
                [strongSelf _doReadWrite];
                break;
            case SSHKitSessionStageUnknown:
                // should never comes to here
                // todo: add a assert protection?
                break;
        }
    }});
    
    dispatch_resume(_readSource);
}

// -----------------------------------------------------------------------------
#pragma mark - Extra Options
// -----------------------------------------------------------------------------

- (BOOL)extraOptionCompression
{
    char* value = NULL;
    int result = ssh_options_get(_rawSession, SSH_OPTIONS_COMPRESSION, &value);
    
    if (SSH_OK==result && value) {
        result = strcasecmp(value, "yes");
        ssh_string_free_char(value);
        
        if ( 0==result ) {
            return YES;
        }
    }
    
    return NO;
}
- (void)setExtraOptionCompression:(BOOL)enabled
{
    if (enabled) {
        ssh_options_set(_rawSession, SSH_OPTIONS_COMPRESSION, "yes");
    } else {
        ssh_options_set(_rawSession, SSH_OPTIONS_COMPRESSION, "no");
    }
}

- (NSString *)extraOptionProxyCommand
{
    char* value = NULL;
    int result = ssh_options_get(_rawSession, SSH_OPTIONS_PROXYCOMMAND, &value);
    
    if (SSH_OK==result && value) {
        NSString *rc = @(value);
        ssh_string_free_char(value);
        
        return rc;
    }
    
    return nil;
}
- (void)setExtraOptionProxyCommand:(NSString *)command
{
    ssh_options_set(_rawSession, SSH_OPTIONS_PROXYCOMMAND, command.UTF8String);
}

#pragma mark - Internal Helpers

// todo: dropbear do not support keepalive message
- (void)_fireKeepAliveTimer
{
    _keepAliveTimer = dispatch_source_create(DISPATCH_SOURCE_TYPE_TIMER, 0, 0, _sessionQueue);
    _keepAliveCounter = 3;
    
    uint64_t interval = SSHKit_SESSION_DEFAULT_TIMEOUT;
    if (_timeout > SSHKit_SESSION_MIN_TIMEOUT) {
        interval = _timeout;
    } else if (_timeout > 0) {
        interval = SSHKit_SESSION_MIN_TIMEOUT;
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
                [strongSelf disconnectWithError:[NSError errorWithDomain:SSHKitSessionErrorDomain
                                                                    code:SSHKitErrorCodeTimeout
                                                                userInfo:@{ NSLocalizedDescriptionKey : @"Timeout, server not responding"} ]];
                return_from_block;
            }
            
            int result = ssh_send_keepalive(strongSelf->_rawSession);
            if (result!=SSH_OK) {
                [strongSelf disconnectWithError:strongSelf.lastError];
                return;
            }
            
            if (!strongSelf.isConnected) {
                [strongSelf disconnectWithError:strongSelf.lastError];
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

- (int)socketFD
{
    return ssh_get_fd(_rawSession);
}

- (void)_resolveHostIP
{
    if (_customSocketFD) {
        return;
    }
    
    struct sockaddr_storage addr;
    socklen_t addr_len=sizeof(addr);
    int err=getpeername(self.socketFD, (struct sockaddr*)&addr, &addr_len);
    
    if (err!=0) {
        return;
    }
    
    char buffer[INET6_ADDRSTRLEN];
    err=getnameinfo((struct sockaddr*)&addr, addr_len, buffer, sizeof(buffer),
                    0, 0, NI_NUMERICHOST);
    
    if (err!=0) {
        return;
    }
    
    self.hostIP = @(buffer);
}

#pragma mark - Open Channels

- (NSArray *)channels
{
    return _channels;
}

- (void)_addChannel:(SSHKitChannel *)channel
{
    [_channels addObject:channel];
}
- (void)_removeChannel:(SSHKitChannel *)channel
{
    [_channels removeObject:channel];
}

- (SSHKitDirectChannel *)openDirectChannelWithHost:(NSString *)host onPort:(uint16_t)port delegate:(id<SSHKitChannelDelegate>)aDelegate
{
    SSHKitDirectChannel *channel = [[SSHKitDirectChannel alloc] initWithSession:self delegate:aDelegate];
    [channel _openWithHost:host onPort:port];
    
    return channel;
}

- (void)requestBindToAddress:(NSString *)address onPort:(uint16_t)port completionBlock:(SSHKitRemotePortForwardBoundBlock)completionBlock;
{
    __weak SSHKitSession *weakSelf = self;
    
    [self dispatchAsyncOnSessionQueue: ^{ @autoreleasepool {
        SSHKitSession *strongSelf = weakSelf;
        if (!strongSelf) {
            return_from_block;
        }
        
        int boundport = 0;
        // todo: listening to ipv4 and ipv6 address respectively
        BOOL rc = ssh_forward_listen(strongSelf.rawSession, address.UTF8String, port, &boundport);
        
        switch (rc) {
            case SSH_OK:
                [strongSelf->_acceptedForwards addObject:@[address, @(boundport)]];
                completionBlock(YES, boundport, nil);
                
                break;
                
            case SSH_AGAIN:
                [strongSelf->_forwardRequests addObject:@[address, @(port), completionBlock]];
                break;
                
            case SSH_ERROR:
            default:
                completionBlock(NO, port, strongSelf.lastError);
                
                break;
        }
    }}];
}

@end
