//
//  SSHKitCoreTests.swift
//  SSHKitCoreTests
//
//  Created by vicalloy on 1/25/16.
//
//

import XCTest

enum AuthMethod: String {
    case Password       = "password"
    case PublicKey      = "publickey"
    case Interactive    = "keyboard-interactive"
}

class SessionTestCase: XCTestCase, SSHKitSessionDelegate {
    let sshHost  = "127.0.0.1"
    let sshPort : UInt16 = 22
    let refusePort : UInt16 = 6009
    
    // for artificially create a connection timeout error
    let nonRoutableIP = "10.255.255.1"
    
    let userForSFA = "sshtest"
    let userForMFA = "sshtest-m"
    let userForNoPass = "sshtest-nopass"
    let invalidUser = "invalid-user"
    
    var password = "v#.%-dzd"
    let invalidPass = "invalid-pass"
    let identity = "ssh_rsa_key"
    
    // async test http://nshipster.com/xctestcase/
    private var authExpectation: XCTestExpectation?
    private var disconnectExpectation: XCTestExpectation?
    
    private var authMethods = [AuthMethod.Password, ]
    
    var hostKey: SSHKitHostKey?
    
    var currentHMAC: String?
    var currentCipher: String?
    var currentKEXAlgo: String?
    
    var error : NSError?
    
    override func setUp() {
        super.setUp()
    }
    
    override func tearDown() {
        super.tearDown()
    }
    
    // MARK: - Connect Utils
    
    private func connectAndReturnSessionWithAuthMethods(methods: [AuthMethod], host: String, port: UInt16, user: String, timeout: NSTimeInterval, options:[String:AnyObject]) throws -> SSHKitSession {
        authExpectation = expectationWithDescription("Launch session with \(methods) auth method")
        authMethods = methods
        
        let session = SSHKitSession(host: host, port: port, user: user, options:options, delegate: self)
        
        session.connectWithTimeout(timeout)
        
        waitForExpectationsWithTimeout(5) { error in
            if let error = error {
                self.error = error
            }
        }
        
        if let error = self.error {
            throw error
        }
        
        return session
    }
    
    func launchSessionWithTimeoutHost(options:[String:AnyObject]=[:]) throws -> SSHKitSession {
        return try connectAndReturnSessionWithAuthMethods([.Password,], host: nonRoutableIP, port: sshPort, user: userForSFA, timeout: 1.5, options: options)
    }
    
    func launchSessionWithRefusePort(options:[String:AnyObject]=[:]) throws -> SSHKitSession {
        return try connectAndReturnSessionWithAuthMethods([.Password,], host: sshHost, port: refusePort, user: userForSFA, timeout: 1, options: options)
    }
    
    func launchSessionWithAuthMethod(method: AuthMethod, user: String, options:[String:AnyObject]=[:]) throws -> SSHKitSession {
        return try connectAndReturnSessionWithAuthMethods([method,], host: sshHost, port: sshPort, user: user, timeout: 1, options: options)
    }
    
    func launchSessionWithAuthMethods(methods: [AuthMethod], user: String, options:[String:AnyObject]=[:]) throws -> SSHKitSession {
        return try connectAndReturnSessionWithAuthMethods(methods, host: sshHost, port: sshPort, user: user, timeout: 1, options: options)
    }
    
    func disconnectSessionAndWait(session: SSHKitSession) throws {
        disconnectExpectation = expectationWithDescription("Disconnect session")
        session.disconnect()
        
        waitForExpectationsWithTimeout(5) { error in
            if let error = error {
                self.error = error
            }
        }
        
        if let error = self.error {
            throw error
        }
    }
    
    // MARK: - SSHKitSessionDelegate
    
    func session(session: SSHKitSession!, didNegotiateWithHMAC hmac: String!, cipher: String!, kexAlgorithm: String!) {
        currentHMAC = hmac;
        currentCipher = cipher;
        currentKEXAlgo = kexAlgorithm;
    }
    
    func session(session: SSHKitSession!, didDisconnectWithError error: NSError!) {
        if error != nil {
            self.error = error
        }
        
        if let expectation = disconnectExpectation {
            expectation.fulfill()
            disconnectExpectation = nil
        }
        
        if let expectation = authExpectation {
            expectation.fulfill()
            authExpectation = nil
        }
    }
    
    func session(session: SSHKitSession!, shouldTrustHostKey hostKey: SSHKitHostKey!) -> Bool {
        self.hostKey = hostKey
        return true
    }
    
    func session(session: SSHKitSession!, didAuthenticateUser username: String!) {
        if let expectation = authExpectation {
            expectation.fulfill()
            authExpectation = nil
        }
    }
    
    func session(session: SSHKitSession!, authenticateWithAllowedMethods methods: [String]!, partialSuccess: Bool) {
        guard let firstMethod = methods.first else {
            XCTFail("authenticateWithAllowedMethods passed in empty auth methods array: \(methods)")
            return
        }
        
        guard let matched = AuthMethod(rawValue: firstMethod) else {
            self.error = NSError(domain: SSHKitCoreErrorDomain, code: SSHKitErrorCode.AuthFailure.rawValue, userInfo: [ NSLocalizedDescriptionKey : "No match authentication method found"])
            return
        }
        
        switch matched {
        case .Password:
            session.authenticateWithAskPassword({ () in
                return self.password
            })
            
        case .PublicKey:
            let publicKeyPath = NSBundle(forClass: self.dynamicType).pathForResource(identity, ofType: "");
            
            do {
                let keyBase64 = try String(contentsOfFile: publicKeyPath!, encoding: NSUTF8StringEncoding)
                let keyPair = try SSHKitKeyPair(fromBase64: keyBase64, withAskPass: nil)
                session.authenticateWithKeyPair(keyPair)
            } catch let error as NSError {
                self.error = error
                return
            }
            
        case .Interactive:
            session.authenticateWithAskInteractiveInfo({
                (index:Int, name:String!, instruction:String!, prompts:[AnyObject]!) -> [AnyObject]! in
                return [self.password];
            })
        }
    }
}
