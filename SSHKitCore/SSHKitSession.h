#import <SSHKitCore/SSHKitCoreCommon.h>

@protocol SSHKitSessionDelegate, SSHKitChannelDelegate;
@class SSHKitChannel, SSHKitHostKeyParser, SSHKitRemoteForwardRequest, SSHKitPrivateKeyParser;

typedef void (^ SSHKitCoreLogHandler)(NSString *fmt, ...);

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
- (instancetype)init;
- (instancetype)initWithDelegate:(id<SSHKitSessionDelegate>)aDelegate;
- (instancetype)initWithDelegate:(id<SSHKitSessionDelegate>)aDelegate sessionQueue:(dispatch_queue_t)sq;

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
@property (nonatomic, readonly) NSString *host;

/** The server actual IP address.
 *  nil if session is connected over proxy
  */
@property (nonatomic, readonly) NSString *hostIP;

/** The server port to connect to. */
@property (nonatomic, readonly) uint16_t port;

/** Username that will authenticate against the server. */
@property (nonatomic, readonly) NSString *username;

@property (strong, readwrite) SSHKitCoreLogHandler logDebug;
@property (strong, readwrite) SSHKitCoreLogHandler logInfo;
@property (strong, readwrite) SSHKitCoreLogHandler logWarn;
@property (strong, readwrite) SSHKitCoreLogHandler logError;
@property (strong, readwrite) SSHKitCoreLogHandler logFatal;

/** The client version string */
@property (nonatomic, readonly)  NSString *clientBanner;

/** Get the software version of the remote server. */
@property (nonatomic, readonly) NSString  *serverBanner;

/** Get the protocol version of remote host. */
@property (nonatomic, readonly) NSString  *protocolVersion;

/**
 A Boolean value indicating whether the session connected successfully
 (read-only).
 */
@property (nonatomic, readonly, getter = isConnected) BOOL connected;
@property (nonatomic, readonly, getter = isDisconnected) BOOL disconnected;

/**
 A Boolean value indicating whether the session is successfully authorized
 (read-only).
 */
@property (nonatomic, readonly, getter = isAuthorized) BOOL authorized;

/** Last session error. */
- (NSError *)coreError;

// -----------------------------------------------------------------------------
#pragma mark Advanced Options, setting before connection
// -----------------------------------------------------------------------------

- (void)enableProxyWithType:(SSHKitProxyType)type host:(NSString *)host port:(uint16_t)port;
- (void)enableProxyWithType:(SSHKitProxyType)type host:(NSString *)host port:(uint16_t)port user:(NSString *)user password:(NSString *)password;

@property BOOL      enableCompression;
@property NSString  *ciphers;
@property NSString  *hostKeyAlgorithms;
@property NSString  *keyExchangeAlgorithms;
@property BOOL      enableIPv4;
@property BOOL      enableIPv6;
@property NSInteger serverAliveCountMax;

// -----------------------------------------------------------------------------
#pragma mark Connecting
// -----------------------------------------------------------------------------

/**
 * Connect to the server using the default timeout (TCP default timeout)
 *
 * This method invokes connectToHost:onPort:withUser:timeout:, and no timeout.
 **/
- (void)connectToHost:(NSString *)host onPort:(uint16_t)port withUser:(NSString*)user;

/**
 * Connects to the given host and port via specified interface with an optional timeout.
 *
 **/
- (void)connectToHost:(NSString *)host onPort:(uint16_t)port viaInterface:(NSString *)interface withUser:(NSString*)user timeout:(NSTimeInterval)timeout;

/**
 * Connects to the given host and port with an optional timeout.
 *
 **/
- (void)connectToHost:(NSString *)host onPort:(uint16_t)port withUser:(NSString*)user timeout:(NSTimeInterval)timeout;

// -----------------------------------------------------------------------------
#pragma mark Disconnecting
// -----------------------------------------------------------------------------

/**
 Close the session
 */
- (void)disconnect;
- (void)impoliteDisconnect;
- (void)disconnectWithError:(NSError *)error;

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
- (void)authenticateByPasswordHandler:(NSString *(^)(void))passwordHandler;

/**
 Authenticate by private key pair

 Use passphraseHandler:nil when the key is unencrypted

 @param privateKeyPath Filepath to private key
 @param passphraseHandler Password handle for encrypted private key
 */
- (void)authenticateByPrivateKeyParser:(SSHKitPrivateKeyParser *)parser;
- (void)authenticateByPrivateKeyBase64:(NSString *)base64;

/**
 Authenticate by keyboard-interactive
 
 @param interactiveHandler Interactive handler for connected user
 */
- (void)authenticateByInteractiveHandler:(NSArray *(^)(NSInteger, NSString *, NSString *, NSArray *))interactiveHandler;

@end

#pragma mark -

/**
 Protocol for registering to receive messages from an active SSHKitSession.
 */
@protocol SSHKitSessionDelegate <NSObject>
@optional

/**
 Called when the session is setup to use keyboard interactive authentication,
 and the server is sending back a question (e.g. a password request).
 
 @param session The session that is asking
 @param request Question from server
 @returns A valid response to the given question
 */
- (NSString *)session:(SSHKitSession *)session keyboardInteractiveRequest:(NSString *)request;


/**
 * Called when a session connects and is ready for reading and writing.
 **/
- (void)session:(SSHKitSession *)session didConnectToHost:(NSString *)host port:(uint16_t)port;

/**
 Called when a session has failed and disconnected.
 
 @param session The session that was disconnected
 @param error A description of the error that caused the disconnect
 */
- (void)session:(SSHKitSession *)session didDisconnectWithError:(NSError *)error;

- (void)session:(SSHKitSession *)session didReceiveIssueBanner:(NSString *)banner;

/**
 Called when a session is connecting to a host, the fingerprint is used
 to verify the authenticity of the host.
 
 @param session The session that is connecting
 @param fingerprint The host's fingerprint
 @returns YES if the session should trust the host, otherwise NO.
 */
- (BOOL)session:(SSHKitSession *)session shouldConnectWithHostKey:(SSHKitHostKeyParser *)hostKey;
- (NSError *)session:(SSHKitSession *)session authenticateWithAllowedMethods:(NSArray *)methods partialSuccess:(BOOL)partialSuccess;
- (void)session:(SSHKitSession *)session didAuthenticateUser:(NSString *)username;

/**
 * Called when ssh server has forward a connection.
 **/
- (void)session:(SSHKitSession *)session didAcceptForwardChannel:(SSHKitChannel *)channel;
@end
