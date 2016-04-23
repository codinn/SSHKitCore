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

class BasicSessionDelegate: XCTestCase, SSHKitSessionDelegate {
    // async test http://nshipster.com/xctestcase/
    var expectation: XCTestExpectation?
    private var authMethods = [AuthMethod.Password, ]
    
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
    
    var error : NSError?
    
    override func setUp() {
        super.setUp()
    }
    
    override func tearDown() {
        // Put teardown code here. This method is called after the invocation of each test method in the class.
        super.tearDown()
    }
    
    // MARK: - Connect Utils
    
    private func connectAndReturnSessionWithAuthMethods(methods: [AuthMethod], host: String, port: UInt16, user: String, timeout: NSTimeInterval) throws -> SSHKitSession {
        expectation = expectationWithDescription("Launch session with \(methods) auth method")
        authMethods = methods
        
        let session = SSHKitSession(host: host, port: port, user: user, delegate: self)
        session.connectWithTimeout(timeout)
        
        waitForExpectationsWithTimeout(5) { error in
            if let error = error {
                XCTFail(error.localizedDescription)
            }
        }
        
        if let error = self.error {
            throw error
        }
        
        return session
    }
    
    func launchSessionWithNonRoutableHost() throws -> SSHKitSession {
        return try connectAndReturnSessionWithAuthMethods([.Password,], host: nonRoutableIP, port: sshPort, user: userForSFA, timeout: 1)
    }
    
    func launchSessionWithRefusePort() throws -> SSHKitSession {
        return try connectAndReturnSessionWithAuthMethods([.Password,], host: sshHost, port: refusePort, user: userForSFA, timeout: 1)
    }
    
    func launchSessionWithAuthMethod(method: AuthMethod, user: String) throws -> SSHKitSession {
        return try connectAndReturnSessionWithAuthMethods([method,], host: sshHost, port: sshPort, user: user, timeout: 1)
    }
    
    func launchSessionWithAuthMethods(methods: [AuthMethod], user: String) throws -> SSHKitSession {
        return try connectAndReturnSessionWithAuthMethods(methods, host: sshHost, port: sshPort, user: user, timeout: 1)
    }
    
    //MARK: - SSHKitSessionDelegate
    
    func session(session: SSHKitSession!, didConnectToHost host: String!, port: UInt16) {
    }
    
    func session(session: SSHKitSession!, didDisconnectWithError error: NSError!) {
        if error != nil {
            self.error = error
            expectation!.fulfill()
        }
    }
    
    func session(session: SSHKitSession!, shouldConnectWithHostKey hostKey: SSHKitHostKey!) -> Bool {
        return true
    }
    
    func session(session: SSHKitSession!, didAuthenticateUser username: String!) {
        expectation!.fulfill()
    }
    
    func session(session: SSHKitSession!, authenticateWithAllowedMethods methods: [String]!, partialSuccess: Bool) -> NSError! {
        guard let firstMethod = methods.first else {
            XCTFail("authenticateWithAllowedMethods passed in empty auth methods array: \(methods)")
            expectation!.fulfill()
            return nil
        }
        
        guard let matched = AuthMethod(rawValue: firstMethod) else {
            let error = NSError(domain: SSHKitCoreErrorDomain, code: SSHKitErrorCode.AuthFailure.rawValue, userInfo: [ NSLocalizedDescriptionKey : "No match authentication method found"])
            expectation!.fulfill()
            return error
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
                return error
            }
            
        case .Interactive:
            session.authenticateWithAskInteractiveInfo({
                (index:Int, name:String!, instruction:String!, prompts:[AnyObject]!) -> [AnyObject]! in
                return [self.password];
            })
        }
        
        return nil
    }
}
