//
//  SSHKitSession.swift
//  SSHKitCore
//
//  Created by vicalloy on 7/11/16.
//
//

import Foundation

var SOCKET_NULL = -1

enum SSHKitSessionStage : Int {
    case Unknown = 0
    case NotConnected
    case Connecting
    case PreAuthenticate
    case Authenticating
    case Authenticated
    case Disconnected
}

/**
 Called when a session negotiated.
 */
public protocol SSHKitSessionDelegate: class{
    /*
     Called when a session negotiated.
     */
    func session(session: SSHKitSession, didNegotiateWithHMAC hmac: String, cipher: String, kexAlgorithm: String);
    
    /**
     Called when a session has failed and disconnected.
     
     @param session The session that was disconnected
     @param error A description of the error that caused the disconnect
     */
    func session(session: SSHKitSession, didDisconnectWithError error: NSError?);
    
    func session(session: SSHKitSession, didReceiveIssueBanner banner: String);
    
    /**
     @param serverBanner Get the software version of the remote server
     @param clientBanner The client version string
     @param protocolVersion Get the protocol version of remote host
     */
    func session(session: SSHKitSession, didReceiveServerBanner serverBanner: String, clientBanner: String, protocolVersion: Int);
    
    /**
     Called when a session is connecting to a host, the fingerprint is used
     to verify the authenticity of the host.
     
     @param session The session that is connecting
     @param fingerprint The host's fingerprint
     @returns YES if the session should trust the host, otherwise NO.
     */
    func session(session: SSHKitSession, shouldTrustHostKey hostKey: SSHKitHostKey) -> Bool;
    
    func session(session: SSHKitSession, authenticateWithAllowedMethods methods: [String], partialSuccess: Bool);
    
    func session(session: SSHKitSession, didAuthenticateUser username: String);
    
    /**
     Called when ssh server has forward a connection.
     **/
    func session(session: SSHKitSession, didOpenForwardChannel channel: SSHKitForwardChannel);
    
    func session(session: SSHKitSession, channel: SSHKitChannel, hasRaisedError error: NSError?);
}

public class SSHKitSession {
    
    /**
     The receiver’s `delegate`.
     
     The `delegate` is sent messages when content is loading.
     */
    weak var delegate: SSHKitSessionDelegate?;
    
    /** Full server hostname in the format `@"{hostname}"`. */
    public private(set) var host: String;
    
    /** The server port to connect to. */
    var port: UInt16;
    
    /** Get the file descriptor of current session connection
     */
    var fd: Int;
    
    /** Username that will authenticate against the server. */
    var username: String;

    /** Advanced options */
    var options: [NSObject : AnyObject];

    /**
     A Boolean value indicating whether the session connected successfully
     (read-only).
     */
    var connected: Bool {
        get {
            var flag: Bool = false
                self.dispatchSyncOnSessionQueue({() -> Void in
                        flag = (self.stage == .Authenticated)
                        })
            return flag
        }
    }

    var disconnected: Bool {
        get {
            var flag: Bool = false
                self.dispatchSyncOnSessionQueue({() -> Void in
                        flag = (self.stage == .NotConnected) || (self.stage == .Unknown) || (self.stage == .Disconnected)
                        })
            return flag
        }
    }
    
    var forwardRequests: [AnyObject]
    var channels: [AnyObject]
    var stage: SSHKitSessionStage;
    private let isOnSessionQueueKey = UnsafePointer<Void>(malloc(1))
    

    private var timeout: Int
    private var sessionQueue: dispatch_queue_t

    init(host: String, port: UInt16, user: String, options: [NSObject : AnyObject], delegate aDelegate: SSHKitSessionDelegate, sessionQueue sq: dispatch_queue_t? = nil) {
        self.host = host
        self.port = port
        self.username = user
        self.options = options
        self.fd = SOCKET_NULL
        self.stage = .NotConnected
        self.channels = []
        self.forwardRequests = []
        self.delegate = aDelegate
        self.timeout = 0
        if let sq = sq {
            assert(sq !== dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_LOW, 0),
                    "The given socketQueue parameter must not be a concurrent queue.");
            assert(sq !== dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_HIGH, 0),
                    "The given socketQueue parameter must not be a concurrent queue.");
            assert(sq !== dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0),
                    "The given socketQueue parameter must not be a concurrent queue.");

            self.sessionQueue = sq;
        } else {
            self.sessionQueue = dispatch_queue_create("com.codinn.libssh.session_queue", DISPATCH_QUEUE_SERIAL);
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
        
        // isOnSessionQueueKey = &isOnSessionQueueKey;
        let nonNullUnusedPointer = toPointer(self)
        dispatch_queue_set_specific(sessionQueue, isOnSessionQueueKey, nonNullUnusedPointer, nil);
    }
    
    // MARK: Configuration
    //
    // MARK: GCD
    func dispatchSyncOnSessionQueue(block: dispatch_block_t) {
        if dispatch_get_specific(isOnSessionQueueKey) != nil {
            block()
        }
        else {
            dispatch_sync(sessionQueue, block)
        }
    }

    func dispatchAsyncOnSessionQueue(block: dispatch_block_t) {
        dispatch_async(sessionQueue, block)
    }
}
