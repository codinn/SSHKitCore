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
    
    let userForSFA = "sshtest"
    let userForMFA = "sshtest-m"
    let userForNoPass = "sshtest-nopass"
    let invalidUser = "invalid-user"
    
    let password = "v#.%-dzd"
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
    
    func launchSessionWithAuthMethod(method: AuthMethod, user: String) throws -> SSHKitSession {
        return try launchSessionWithAuthMethods([method,], user: user)
    }
    
    func launchSessionWithAuthMethods(methods: [AuthMethod], user: String) throws -> SSHKitSession {
        expectation = expectationWithDescription("Launch session with \(methods) auth method")
        authMethods = methods
        
        let session = SSHKitSession(host: sshHost, port: sshPort, user: user, delegate: self)
        session.connectWithTimeout(1)
        
        waitForExpectationsWithTimeout(1) { error in
            if let error = error {
                XCTFail(error.localizedDescription)
            }
        }
        
        if let error = self.error {
            throw error
        }
        
        return session
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
        if partialSuccess {
            // self.logInfo("Partial success. Authentication that can continue: %@", methods.componentsJoinedByString(", "))
        } else {
            // self.logInfo("Authentication that can continue: %@", methods.componentsJoinedByString(", "))
        }
        
        if let firstMethod = methods.first {
            if let matched = AuthMethod(rawValue: firstMethod) {
                switch matched {
                case .Password:
                    session.authenticateWithAskPassword({
                        () in
                        return self.password
                    })
                    
                case .PublicKey:
                    let publicKeyPath = NSBundle(forClass: self.dynamicType).pathForResource(identity, ofType: "");
                    
                    do {
                        let keyBase64 = try String(contentsOfFile: publicKeyPath!, encoding: NSUTF8StringEncoding)
                        let keyPair = try SSHKitKeyPair(fromBase64: keyBase64, withAskPass: nil)
                        session.authenticateWithKeyPair(keyPair)
                    } catch let error as NSError {
                        XCTFail(error.description)
                    }
                    
                case .Interactive:
                    session.authenticateWithAskInteractiveInfo({
                        (index:Int, name:String!, instruction:String!, prompts:[AnyObject]!) -> [AnyObject]! in
                        return [self.password];
                    })
                }
            } else {
                XCTFail("No match authentication method found: \(firstMethod)")
                expectation!.fulfill()
                return nil
            }
        } else {
            XCTFail("authenticateWithAllowedMethods passed in empty auth methods array: \(methods)")
            expectation!.fulfill()
        }
        
        return nil
    }
}
