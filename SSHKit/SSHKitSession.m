#import "SSHKitSession.h"
#import "SSHKit+Protected.h"
#import <libssh/libssh.h>
#import <libssh/callbacks.h>
#import <libssh/server.h>

@interface SSHKitSession () {
	struct {
		unsigned int keyboardInteractiveRequest     : 1;
		unsigned int didConnectToHostPort           : 1;
		unsigned int didDisconnectWithError         : 1;
		unsigned int shouldConnectWithHostKeyType   : 1;
		unsigned int didAuthenticateUser            : 1;
		unsigned int didFailToAuthenticateUser      : 1;
        unsigned int passphraseForPrivateKey        : 1;
        unsigned int didFailToDecryptPrivateKey     : 1;
        unsigned int needAuthenticateUser           : 1;
	} _delegateFlags;
    
	dispatch_source_t _readSource;
    dispatch_source_t _diagnosesTimer;
    NSInteger _keepAliveCounter;
    NSMutableArray *_channels;
    
    void *_isOnSessionQueueKey;
    
    // make sure disconnect only once
    BOOL _alreadyDidDisconnect;
    
    SSHKitGetSocketFDBlock _socketFDBlock;
}

@property (nonatomic, strong) NSString      *host;
@property (nonatomic, readwrite) uint16_t   port;
@property (nonatomic, strong) NSString      *username;
@property (nonatomic, readwrite) NSString   *privateKeyPath;

@property (nonatomic, readonly) long        timeout;

@property (nonatomic, readwrite) NSInteger authMethods;

@property (atomic, strong, readwrite) dispatch_queue_t sessionQueue;
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
	return [self initWithDelegate:nil sessionQueue:NULL socketFDBlock:NULL];
}

- (instancetype)initWithDelegate:(id<SSHKitSessionDelegate>)aDelegate
{
	return [self initWithDelegate:aDelegate sessionQueue:NULL socketFDBlock:NULL];
}

- (instancetype)initWithDelegate:(id<SSHKitSessionDelegate>)aDelegate socketFDBlock:(SSHKitGetSocketFDBlock)socketFDBlock
{
    return [self initWithDelegate:aDelegate sessionQueue:NULL socketFDBlock:socketFDBlock];
}

- (instancetype)initWithDelegate:(id<SSHKitSessionDelegate>)aDelegate sessionQueue:(dispatch_queue_t)sq
{
    return [self initWithDelegate:aDelegate sessionQueue:sq socketFDBlock:NULL];
}

- (instancetype)initWithDelegate:(id<SSHKitSessionDelegate>)aDelegate sessionQueue:(dispatch_queue_t)sq socketFDBlock:(SSHKitGetSocketFDBlock)socketFDBlock
{
    if ((self = [super init])) {
        _socketFDBlock = socketFDBlock;
        
        _rawSession = ssh_new();
        
        if (!_rawSession) {
            return nil;
        }
        
        _channels = [@[] mutableCopy];
        
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
        ssh_free(_rawSession);
        _rawSession= NULL;
	}];
}

#pragma mark Configuration

- (void)setDelegate:(id<SSHKitSessionDelegate>)delegate
{
	if (_delegate != delegate) {
		_delegate = delegate;
        _delegateFlags.needAuthenticateUser = [delegate respondsToSelector:@selector(session:needAuthenticateUser:)];
		_delegateFlags.didAuthenticateUser = [delegate respondsToSelector:@selector(session:didAuthenticateUser:)];
		_delegateFlags.didConnectToHostPort = [delegate respondsToSelector:@selector(session:didConnectToHost:port:)];
		_delegateFlags.didDisconnectWithError = [delegate respondsToSelector:@selector(session:didDisconnectWithError:)];
		_delegateFlags.didFailToAuthenticateUser = [delegate respondsToSelector:@selector(session:didFailToAuthenticateUser:withError:)];
		_delegateFlags.keyboardInteractiveRequest = [delegate respondsToSelector:@selector(session:keyboardInteractiveRequest:)];
		_delegateFlags.shouldConnectWithHostKeyType = [delegate respondsToSelector:@selector(session:shouldConnectWithHostKey:keyType:)];
		_delegateFlags.passphraseForPrivateKey = [delegate respondsToSelector:@selector(session:passphraseForPrivateKey:)];
        _delegateFlags.didFailToDecryptPrivateKey = [delegate respondsToSelector:@selector(session:didFailToDecryptPrivateKey:)];
	}
}

// -----------------------------------------------------------------------------
#pragma mark Connecting
// -----------------------------------------------------------------------------

- (NSError *)_checkHostKey
{
    ssh_key host_key;
    int rc = ssh_get_publickey(_rawSession, &host_key);
    if (rc < 0) {
        NSError *error = [NSError errorWithDomain:SSHKitSessionErrorDomain
                                             code:SSHKitErrorCodeHostKeyError
                                         userInfo:@{ NSLocalizedDescriptionKey : @"Cannot decode server host key" }];
        return error;
    }
    
    NSString *hostKey = SSHKitGetBase64FromHostKey(host_key);
    SSHKitHostKeyType keyType = (SSHKitHostKeyType)ssh_key_type(host_key);
    
    ssh_key_free(host_key);
    if (!hostKey.length) {
        NSError *error = [NSError errorWithDomain:SSHKitSessionErrorDomain
                                             code:SSHKitErrorCodeHostKeyError
                                         userInfo:@{ NSLocalizedDescriptionKey :@"Cannot verify server host key" }];
        return error;
    }
    
    if (hostKey && _delegateFlags.shouldConnectWithHostKeyType && [self.delegate session:self shouldConnectWithHostKey:hostKey keyType:keyType])
    {
        // success
        return nil;
    }
    
    return [NSError errorWithDomain:SSHKitSessionErrorDomain
                               code:SSHKitErrorCodeHostKeyError
                           userInfo:@{ NSLocalizedDescriptionKey : @"Server host key verification failed" }];;
}

- (void)_doConnect
{
#if DEBUG
    int verbosity = SSH_LOG_FUNCTIONS;
#else
    int verbosity = SSH_LOG_NOLOG;
#endif
    ssh_options_set(_rawSession, SSH_OPTIONS_LOG_VERBOSITY, &verbosity);
    
    ssh_options_set(_rawSession, SSH_OPTIONS_HOSTKEYS,
                    "ssh-rsa,ssh-dss,"
                    "ecdsa-sha2-nistp256-cert-v01@openssh.com,"
                    "ecdsa-sha2-nistp384-cert-v01@openssh.com,"
                    "ecdsa-sha2-nistp521-cert-v01@openssh.com,"
                    "ssh-rsa-cert-v01@openssh.com,ssh-dss-cert-v01@openssh.com,"
                    "ssh-rsa-cert-v00@openssh.com,ssh-dss-cert-v00@openssh.com,"
                    "ecdsa-sha2-nistp256,ecdsa-sha2-nistp384,ecdsa-sha2-nistp521"
                    );
    if (_timeout > 0) {
        ssh_options_set(_rawSession, SSH_OPTIONS_TIMEOUT, &_timeout);
    }
    
    // disconnect if connected
    if (self.isConnected) {
        [self disconnect];
    }
    
    int result = ssh_connect(_rawSession);
    
    if ( SSH_OK == result ) {
        [self _resolveHostIP];
        NSError *error = [self _checkHostKey];
        
        if (error) {
            [self disconnectWithError:error];
            return;
        }
        
        if (_delegateFlags.didConnectToHostPort) {
            [self.delegate session:self didConnectToHost:self.host port:self.port];
        }
        
        // must call this method before next auth method, or libssh will be failed
        int rc = ssh_userauth_none(_rawSession, NULL);
        
        if (rc==SSH_AUTH_DENIED) {
            self.authMethods = ssh_userauth_list(_rawSession, NULL);
            
            if (_delegateFlags.needAuthenticateUser) {
                [self.delegate session:self needAuthenticateUser:nil];
                
                // Handoff to next auth method
                return;
            }
        }
        
        [self _checkAuthenticateResult:rc];
    } else {
        [self disconnectWithError:self.lastError];
    }
}

- (void)connectToHost:(NSString *)host onPort:(uint16_t)port withUser:(NSString*)user
{
    [self connectToHost:host onPort:port withUser:(NSString*)user timeout:0.0];
}

- (void)connectToHost:(NSString *)host onPort:(uint16_t)port withUser:(NSString *)user timeout:(NSTimeInterval)timeout
{
    self.host = host;
    self.port = port;
    self.username = user;
    _timeout = (long)timeout;
    
//    __weak SSHKitSession *weakSelf = self;
    [self dispatchAsyncOnSessionQueue: ^{ @autoreleasepool {
//        __strong SSHKitSession *strongSelf = weakSelf;
        // set to blocking mode
        ssh_set_blocking(_rawSession, 1);
        
        if (_socketFDBlock) {
            // libssh will close this fd automatically
            socket_t socket_fd =_socketFDBlock(_host, _port);
            ssh_options_set(_rawSession, SSH_OPTIONS_FD, &socket_fd);
        }
        
        ssh_options_set(_rawSession, SSH_OPTIONS_HOST, _host.UTF8String);
        ssh_options_set(_rawSession, SSH_OPTIONS_PORT, &_port);
        ssh_options_set(_rawSession, SSH_OPTIONS_USER, _username.UTF8String);
        
        [self _doConnect];
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
        int status = ssh_get_status(_rawSession);
        
        if ( (status & SSH_CLOSED_ERROR) || (status & SSH_CLOSED) || (ssh_is_connected(_rawSession) == 0) ) {
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
        [self _invalidateDiagnosesTimer];
        
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
        [self _invalidateDiagnosesTimer];
        
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
    
    [self dispatchSyncOnSessionQueue :^{ @autoreleasepool {
        SSHKitErrorCode code = SSHKitErrorCodeNoError;
        int errorCode = ssh_get_error_code(_rawSession);
        
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
        
        const char* errorStr = ssh_get_error(_rawSession);
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

- (void)_failedToAuthenticateWithError:(NSError *)error
{
    [self disconnectWithError:error];
    
    if (_delegateFlags.didFailToAuthenticateUser) {
        [self.delegate session:self didFailToAuthenticateUser:self.username withError:error];
    }
}

- (void)_didAuthenticate
{
    // enabling non-blocking mode
    ssh_set_blocking(_rawSession, 0);
    
    // start diagnoses timer
    [self _fireDiagnosesTimer];
    
    [self _doEndlessRead];
    
    if (_delegateFlags.didAuthenticateUser) {
        [self.delegate session:self didAuthenticateUser:self.username];
    }
}

- (BOOL)_checkAuthenticateResult:(NSInteger)result
{
    switch (result) {
        case SSH_AUTH_DENIED:
            [self _failedToAuthenticateWithError:self.lastError];
            return NO;
            
        case SSH_AUTH_ERROR:
            [self _failedToAuthenticateWithError:self.lastError];
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
            [self _failedToAuthenticateWithError:[NSError errorWithDomain:SSHKitSessionErrorDomain
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

- (void)authenticateByPassword:(NSString *)password
{
    __weak SSHKitSession *weakSelf = self;
    [self dispatchAsyncOnSessionQueue: ^{ @autoreleasepool {
        __strong SSHKitSession *strongSelf = weakSelf;
        
        if ( ! ( (strongSelf.authMethods & SSHKitSessionUserAuthInteractive) || (strongSelf.authMethods & SSHKitSessionUserAuthPassword) ) )
        {
            NSError *error = [NSError errorWithDomain:SSHKitSessionErrorDomain
                                                 code:SSHKitErrorCodeAuthError
                                             userInfo:@{ NSLocalizedDescriptionKey : @"Password and interactive auth methods are not supported by SSH server" }];
            [strongSelf _failedToAuthenticateWithError:error];
            return;
        }
        
        // try keyboard-interactive method
        if (strongSelf.authMethods & SSHKitSessionUserAuthInteractive)
        {
            int rc = ssh_userauth_kbdint(_rawSession, NULL, NULL);
            while (rc == SSH_AUTH_INFO)
            {
                ssh_userauth_kbdint_getname(_rawSession);
                ssh_userauth_kbdint_getinstruction(_rawSession);
                int nprompts = ssh_userauth_kbdint_getnprompts(_rawSession);
                
                for (int i = 0; i < nprompts; i++) {
                    char echo;
                    ssh_userauth_kbdint_getprompt(_rawSession, i, &echo);
                    
                    if (ssh_userauth_kbdint_setanswer(_rawSession, i, password.UTF8String) < 0) {
                        break;
                    }
                }
                rc = ssh_userauth_kbdint(_rawSession, NULL, NULL);
            }
            
            
            if (rc!=SSH_AUTH_DENIED) {
                [strongSelf _checkAuthenticateResult:rc];
                return;
            }
            
            // try next - password method
        }
        
        // continue try "password" method, which is deprecated in SSH 2.0
        if (strongSelf.authMethods & SSHKitSessionUserAuthPassword )
        {
            int rc = ssh_userauth_password(_rawSession, NULL, password.UTF8String);
            [strongSelf _checkAuthenticateResult:rc];
            return;
        }
        
        // never reach here
        [strongSelf disconnectWithError:[NSError errorWithDomain:SSHKitSessionErrorDomain
                                                            code:SSHKitErrorCodeAuthError
                                                        userInfo:@{ NSLocalizedDescriptionKey : @"Unknown error while authenticate user"} ]];
    }}];
}

static int _askPassphrase(const char *prompt, char *buf, size_t len, int echo, int verify, void *userdata)
{
    if (!userdata) {
        return SSH_ERROR;
    }
    
    SSHKitSession *session = (__bridge SSHKitSession *) userdata;
    
    if (!session->_delegateFlags.passphraseForPrivateKey) {
        return SSH_ERROR;
    }
    
    NSString *password = [session.delegate session:session passphraseForPrivateKey:session.privateKeyPath];
    if (password.length && password.length<len) {
        strcpy(buf, password.UTF8String);
        return SSH_OK;
    }
    
    return SSH_ERROR;
}

- (void)authenticateByPrivateKey:(NSString *)privateKeyPath
{
    if ( !(self.authMethods & SSHKitSessionUserAuthPublickey) ) {
        NSError *error = [NSError errorWithDomain:SSHKitSessionErrorDomain
                                    code:SSHKitErrorCodeAuthError
                                userInfo:@{ NSLocalizedDescriptionKey : @"Publickey auth method is not supported by SSH server" }];
        [self _failedToAuthenticateWithError:error];
        return;
    }
    
    if (!privateKeyPath) {
        NSError *error = [NSError errorWithDomain:SSHKitSessionErrorDomain
                                             code:SSHKitErrorCodeAuthError
                                         userInfo:@{ NSLocalizedDescriptionKey : @"Path of private key is not specified" }];
        [self _failedToAuthenticateWithError:error];
        return;
    }
    
    self.privateKeyPath = privateKeyPath;
    __weak SSHKitSession *weakSelf = self;
    
    [self dispatchAsyncOnSessionQueue: ^{ @autoreleasepool {
        __strong SSHKitSession *strongSelf = weakSelf;
        ssh_key rawPrivateKey = NULL;
        ssh_key rawPublicKey = NULL;
        
        // import private key
        int ret = ssh_pki_import_privkey_file(strongSelf.privateKeyPath.UTF8String, NULL, _askPassphrase, (__bridge void *)(strongSelf), &rawPrivateKey);
        
        if (ret!=SSH_OK) {
            NSError *error;
            
            if (ret==SSH_EOF) {
                error = [NSError errorWithDomain:SSHKitSessionErrorDomain
                                            code:SSHKitErrorCodeAuthError
                                        userInfo:@{ NSLocalizedDescriptionKey : @"Private key file doesn't exist or permission denied" }];
            } else {
                error = [NSError errorWithDomain:SSHKitSessionErrorDomain
                                            code:SSHKitErrorCodeAuthError
                                        userInfo:@{ NSLocalizedDescriptionKey : @"Could not load and parse private key file" }];
                if (_delegateFlags.didFailToDecryptPrivateKey) {
                    [self.delegate session:self didFailToDecryptPrivateKey:privateKeyPath];
                }
            }
            
            [strongSelf _failedToAuthenticateWithError:error];
            goto _exit_block;
        }
        
        // extract public key from private key
        ret = ssh_pki_export_privkey_to_pubkey(rawPrivateKey, &rawPublicKey);
        
        if (ret!=SSH_OK) {
            NSError *error = [NSError errorWithDomain:SSHKitSessionErrorDomain
                                                 code:SSHKitErrorCodeAuthError
                                             userInfo:@{ NSLocalizedDescriptionKey : [NSString stringWithFormat:@"Could not extract public key from \"%@\"", strongSelf.privateKeyPath] }];
            [strongSelf _failedToAuthenticateWithError:error];
            goto _exit_block;
        }
        
        // try public key
        ret = ssh_userauth_try_publickey(_rawSession, NULL, rawPublicKey);
        if (ret!=SSH_AUTH_SUCCESS) {
            [strongSelf _checkAuthenticateResult:ret];
            goto _exit_block;
        }
        
        // authenticate using private key
        ret = ssh_userauth_publickey(_rawSession, NULL, rawPrivateKey);
        [strongSelf _checkAuthenticateResult:ret];
        
    _exit_block:
        if (rawPrivateKey) {
            ssh_key_free(rawPrivateKey);
        }
        
        if (rawPublicKey) {
            ssh_key_free(rawPublicKey);
        }
    }}];
}

// -----------------------------------------------------------------------------
#pragma mark - CALLBACKS
// -----------------------------------------------------------------------------

/**
 * Reads the first available bytes that become available on the channel.
 **/
- (void)_doEndlessRead
{
    if (_readSource) {
        dispatch_source_cancel(_readSource);
    }
    
    _readSource = dispatch_source_create(DISPATCH_SOURCE_TYPE_READ, self.socketFD, 0, _sessionQueue);
    
    __weak SSHKitSession *weakSelf = self;
    dispatch_source_set_event_handler(_readSource, ^{ @autoreleasepool {
        __strong SSHKitSession *strongSelf = weakSelf;
        
        _keepAliveCounter = 3;
        
        if (!strongSelf.isConnected) {
            [strongSelf disconnectWithError:strongSelf.lastError];
        }
        
        if (strongSelf.channels.count) {
            NSArray *channels = [strongSelf.channels copy];
            
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

- (void)_fireDiagnosesTimer
{
    _diagnosesTimer = dispatch_source_create(DISPATCH_SOURCE_TYPE_TIMER, 0, 0, _sessionQueue);
    _keepAliveCounter = 3;
    
    uint64_t interval = SSHKit_SESSION_DEFAULT_TIMEOUT;
    if (_timeout > SSHKit_SESSION_MIN_TIMEOUT) {
        interval = _timeout;
    } else if (_timeout > 0) {
        interval = SSHKit_SESSION_MIN_TIMEOUT;
    }
    
    if (_diagnosesTimer)
    {
        dispatch_source_set_timer(_diagnosesTimer, dispatch_time(DISPATCH_TIME_NOW, interval * NSEC_PER_SEC), interval * NSEC_PER_SEC, (1ull * NSEC_PER_SEC) / 10);
        
        __weak SSHKitSession *weakSelf = self;
        dispatch_source_set_event_handler(_diagnosesTimer, ^{
            __strong SSHKitSession *strongSelf = weakSelf;
            
            if (_keepAliveCounter<=0) {
                [strongSelf disconnectWithError:[NSError errorWithDomain:SSHKitSessionErrorDomain
                                                                    code:SSHKitErrorCodeTimeout
                                                                userInfo:@{ NSLocalizedDescriptionKey : @"Timeout, server not responding"} ]];
                return;
            }
            
            int result = ssh_send_keepalive(_rawSession);
            if (result!=SSH_OK) {
                [strongSelf disconnectWithError:strongSelf.lastError];
                return;
            }
            
            if (!strongSelf.isConnected) {
                [strongSelf disconnectWithError:strongSelf.lastError];
                return;
            }
            
            _keepAliveCounter--;
        });
        
        dispatch_resume(_diagnosesTimer);
    }
}

- (void)_invalidateDiagnosesTimer
{
    if (_diagnosesTimer) {
        dispatch_source_cancel(_diagnosesTimer);
        _diagnosesTimer = nil;
    }
}

- (int)socketFD
{
    return ssh_get_fd(_rawSession);
}

- (void)_resolveHostIP
{
    if (_socketFDBlock) {
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
    
    _hostIP = @(buffer);
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

- (SSHKitDirectTCPIPChannel *)openDirectChannelWithHost:(NSString *)host onPort:(uint16_t)port delegate:(id<SSHKitChannelDelegate>)aDelegate
{
    SSHKitDirectTCPIPChannel *channel = [[SSHKitDirectTCPIPChannel alloc] initWithSession:self delegate:aDelegate];
    [channel _openWithHost:host onPort:port];
    
    return channel;
}

@end
