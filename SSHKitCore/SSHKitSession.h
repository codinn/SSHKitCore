#import <SSHKitCore/SSHKitCoreCommon.h>

@protocol SSHKitSessionDelegate, SSHKitChannelDelegate, SSHKitShellChannelDelegate;
@class SSHKitHostKey, SSHKitRemoteForwardRequest, SSHKitKeyPair;
@class SSHKitChannel, SSHKitDirectChannel, SSHKitForwardChannel, SSHKitShellChannel, SSHKitSFTPChannel;

typedef void (^ SSHKitLogHandler)(SSHKitLogLevel level, NSString *fmt, ...);

// -----------------------------------------------------------------------------
#pragma mark -
// -----------------------------------------------------------------------------

/**
 ## Thread safety

 SSHKit classes are not thread safe, you should use them from the same thread
 where you created the SSHKitSession instance.
 */
@interface SSHKitSession : NSObject

/// ----------------------------------------------------------------------------
/// @name Initialize a new SSH session
/// ----------------------------------------------------------------------------

/**
 * SSHKitSession uses the standard delegate paradigm,
 * but executes all delegate callbacks on a given delegate dispatch queue.
 * This allows for maximum concurrency, while at the same time providing easy thread safety.
 *
 * You MUST set a delegate AND delegate dispatch queue before attempting to
 * use the session, or you will get an error.
 *
 * The session queue is optional.
 * If you pass NULL, SSHKitSession will automatically create it's own socket queue.
 * If you choose to provide a session queue, the session queue must not be a concurrent queue.
 * If you choose to provide a session queue, and the session queue has a configured target queue,
 *
 **/
- (instancetype)initWithHost:(NSString *)host port:(uint16_t)port user:(NSString *)user options:(NSDictionary *)options delegate:(id<SSHKitSessionDelegate>)aDelegate;
- (instancetype)initWithHost:(NSString *)host port:(uint16_t)port user:(NSString *)user options:(NSDictionary *)options delegate:(id<SSHKitSessionDelegate>)aDelegate sessionQueue:(dispatch_queue_t)sq;

// -----------------------------------------------------------------------------
#pragma mark Configuration
// -----------------------------------------------------------------------------

/**
 The receiver’s `delegate`.

 The `delegate` is sent messages when content is loading.
 */
@property (nonatomic, weak) id<SSHKitSessionDelegate> delegate;

// -----------------------------------------------------------------------------
#pragma mark Diagnostics
// -----------------------------------------------------------------------------

/** Full server hostname in the format `@"{hostname}"`. */
@property (nonatomic, readonly) NSString        *host;

/** The server port to connect to. */
@property (nonatomic, readonly) uint16_t        port;

/** Get the file descriptor of current session connection
 */
@property (nonatomic, readonly) int             fd;

/** Username that will authenticate against the server. */
@property (nonatomic, readonly) NSString        *username;

/** Advanced options */
@property (nonatomic, readonly) NSDictionary    *options;

@property (strong, readwrite) SSHKitLogHandler logHandle;

/**
 A Boolean value indicating whether the session connected successfully
 (read-only).
 */
@property (nonatomic, readonly, getter = isConnected) BOOL connected;
@property (nonatomic, readonly, getter = isDisconnected) BOOL disconnected;

// -----------------------------------------------------------------------------
#pragma mark Connecting
// -----------------------------------------------------------------------------

/**
 * Connects to the given host and port with an optional timeout.
 * @param timeout Using 0.0 set default timeout (TCP default timeout)
 *
 **/
- (void)connectWithTimeout:(NSTimeInterval)timeout;
/**
 * Connects to the server via an opened socket.
 *
 **/
- (void)connectWithTimeout:(NSTimeInterval)timeout viaFileDescriptor:(int)fd;

// -----------------------------------------------------------------------------
#pragma mark Disconnecting
// -----------------------------------------------------------------------------

/**
 Close the session
 */
- (void)disconnect;

// -----------------------------------------------------------------------------
#pragma mark GCD
// -----------------------------------------------------------------------------

- (void)dispatchSyncOnSessionQueue:(dispatch_block_t)block;
- (void)dispatchAsyncOnSessionQueue:(dispatch_block_t)block;

// -----------------------------------------------------------------------------
#pragma mark Authentication
// -----------------------------------------------------------------------------

/**
 Authenticate by password

 @param passwordHandler Password handler for get password
 */
- (void)authenticateWithAskPassword:(NSString *(^)(void))passwordHandler;

/**
 Authenticate by private key pair

 Use askPass:nil when the key is unencrypted

 @param privateKeyPath Filepath to private key
 @param askPass Password handle for encrypted private key
 */
- (void)authenticateWithKeyPair:(SSHKitKeyPair *)keyPair;

/**
 Authenticate by keyboard-interactive
 
 @param interactiveHandler Interactive handler for connected user
 */
- (void)authenticateWithAskInteractiveInfo:(NSArray *(^)(NSInteger, NSString *, NSString *, NSArray *))interactiveHandler;

@end

#pragma mark -

/**
 Protocol for registering to receive messages from an active SSHKitSession.
 */
@protocol SSHKitSessionDelegate <NSObject>
@optional

/**
 * Called when a session negotiated.
 **/
- (void)session:(SSHKitSession *)session didNegotiateWithHMAC:(NSString *)hmac cipher:(NSString *)cipher kexAlgorithm:(NSString *)kexAlgorithm;

/**
 Called when a session has failed and disconnected.
 
 @param session The session that was disconnected
 @param error A description of the error that caused the disconnect
 */
- (void)session:(SSHKitSession *)session didDisconnectWithError:(NSError *)error;

- (void)session:(SSHKitSession *)session didReceiveIssueBanner:(NSString *)banner;


/**
 @param serverBanner Get the software version of the remote server
 @param clientBanner The client version string
 @param protocolVersion Get the protocol version of remote host
 */
- (void)session:(SSHKitSession *)session didReceiveServerBanner:(NSString *)serverBanner clientBanner:(NSString *)clientBanner protocolVersion:(int)protocolVersion;

/**
 Called when a session is connecting to a host, the fingerprint is used
 to verify the authenticity of the host.
 
 @param session The session that is connecting
 @param fingerprint The host's fingerprint
 @returns YES if the session should trust the host, otherwise NO.
 */
- (BOOL)session:(SSHKitSession *)session shouldTrustHostKey:(SSHKitHostKey *)hostKey;
- (NSError *)session:(SSHKitSession *)session authenticateWithAllowedMethods:(NSArray<NSString *> *)methods partialSuccess:(BOOL)partialSuccess;

- (void)session:(SSHKitSession *)session didAuthenticateUser:(NSString *)username;

/**
 * Called when ssh server has forward a connection.
 **/
- (void)session:(SSHKitSession *)session didOpenForwardChannel:(SSHKitForwardChannel *)channel;
@end
