#import "SSHKitCore.h"

NS_OPTIONS(NSInteger, SSHKitSessionUserAuthMethods) {
    SSHKitSessionUserAuthUnknown     = 0,
    SSHKitSessionUserAuthNone        = 1 << 0,
    SSHKitSessionUserAuthPassword    = 1 << 1,
    SSHKitSessionUserAuthPublickey   = 1 << 2,
    SSHKitSessionUserAuthHostbased   = 1 << 3,
    SSHKitSessionUserAuthInteractive = 1 << 4,
    SSHKitSessionUserAuthGSSAPIMic   = 1 << 5,
};

@protocol SSHKitSessionDelegate, SSHKitChannelDelegate;
@class SSHKitDirectChannel, SSHKitForwardChannel;

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
- (instancetype)initWithDelegate:(id<SSHKitSessionDelegate>)aDelegate socketFDBlock:(SSHKitGetSocketFDBlock)socketFDBlock;
- (instancetype)initWithDelegate:(id<SSHKitSessionDelegate>)aDelegate sessionQueue:(dispatch_queue_t)sq;
- (instancetype)initWithDelegate:(id<SSHKitSessionDelegate>)aDelegate sessionQueue:(dispatch_queue_t)sq socketFDBlock:(SSHKitGetSocketFDBlock)socketFDBlock;


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

/** supported authentication methods */
@property (nonatomic, readonly) NSInteger authMethods;

/** Full server hostname in the format `@"{hostname}"`. */
@property (nonatomic, readonly) NSString *host;

/** The server actual IP address. */
@property (nonatomic, readonly) NSString *hostIP;

/** The server port to connect to. */
@property (nonatomic, readonly) uint16_t port;

/** Username that will authenticate against the server. */
@property (nonatomic, readonly) NSString *username;

/** Private key that will authenticate against the server. */
@property (nonatomic, readonly) NSString *privateKeyPath;

/** Last session error. */
@property (nonatomic, readonly) NSError *lastError;

/** The banner that will be sent to the remote host when the SSH session is started. */
@property (nonatomic, strong) NSString *banner;

/** The remote host banner. */
@property (nonatomic, readonly) NSString *remoteBanner;

/**
 A Boolean value indicating whether the session connected successfully
 (read-only).
 */
@property (nonatomic, readonly, getter = isConnected) BOOL connected;

/**
 A Boolean value indicating whether the session is successfully authorized
 (read-only).
 */
@property (nonatomic, readonly, getter = isAuthorized) BOOL authorized;

/**
 *
 * Opened channels
 */
@property (readonly) NSArray *channels;

// -----------------------------------------------------------------------------
#pragma mark Advanced Options
// -----------------------------------------------------------------------------

@property BOOL      extraOptionCompression;
@property NSString  *extraOptionProxyCommand;

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
- (void)disconnectAsync;


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

 @param password Password for connected user
 */
- (void)authenticateByPassword:(NSString *)password;

/**
 Authenticate by private key pair

 Use passphraseHandle:nil when the key is unencrypted

 @param privateKeyPath Filepath to private key
 @param passphraseHandle Password handle for encrypted private key
 */
- (void)authenticateByPrivateKey:(NSString *)privateKeyPath passphraseHandle:(SSHKitAskPassphrasePrivateKeyBlock)handler;

+ (SSHKitPrivateKeyTestResult)testPrivateKeyPath:(NSString *)privateKeyPath passphraseHandle:(SSHKitAskPassphrasePrivateKeyBlock)handler;

#pragma mark - Open Channels

- (SSHKitDirectChannel *)openDirectChannelWithHost:(NSString *)host onPort:(uint16_t)port delegate:(id<SSHKitChannelDelegate>)aDelegate;

- (void)requestBindToAddress:(NSString *)address onPort:(uint16_t)port;

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

/**
 Called when a session is connecting to a host, the fingerprint is used
 to verify the authenticity of the host.
 
 @param session The session that is connecting
 @param fingerprint The host's fingerprint
 @returns YES if the session should trust the host, otherwise NO.
 */
- (BOOL)session:(SSHKitSession *)session shouldConnectWithHostKey:(NSString *)hostKey keyType:(SSHKitHostKeyType)keyType;
- (void)session:(SSHKitSession *)session needAuthenticateUser:(NSString *)username;
- (void)session:(SSHKitSession *)session didAuthenticateUser:(NSString *)username;
- (void)session:(SSHKitSession *)session didFailToAuthenticateUser:(NSString *)username withError:(NSError *)error;

/**
 * Called when ssh server has handled forward-tcpip request.
 **/
- (void)session:(SSHKitSession *)session didBindToAddress:(NSString *)address port:(uint16_t)port boundPort:(uint16_t)boundPort;
- (void)session:(SSHKitSession *)session didFailToBindToAddress:(NSString *)address port:(uint16_t)port withError:(NSError *)error;

/**
 * Called when ssh server has forward a connection.
 **/
- (void)session:(SSHKitSession *)session didAcceptForwardChannel:(SSHKitForwardChannel *)channel;
@end
