//
//  ConnectTests.swift
//  SSHKitCore
//
//  Created by vicalloy on 2/21/16.
//
//

import XCTest

class SessionTests: SessionTestCase {

    override func setUp() {
        super.setUp()
        // Put setup code here. This method is called before the invocation of each test method in the class.
    }
    
    override func tearDown() {
        // Put teardown code here. This method is called after the invocation of each test method in the class.
        super.tearDown()
    }
    
    // MARK: - Connect
    
    func testSessionConnectWithNonRoutableIP() {
        do {
            let session = try launchSessionWithNonRoutableHost()
            XCTAssertNotNil(session)
        } catch let error as NSError {
            XCTAssertEqual(SSHKitErrorCode.Timeout.rawValue, error.code, error.description)
            return
        }
        
        XCTFail("An connect error not raised as expected")
    }
    
    func testSessionConnectWithRefusePort() {
        do {
            let session = try launchSessionWithRefusePort()
            XCTAssertNotNil(session)
        } catch let error as NSError {
            XCTAssertEqual(SSHKitErrorCode.Fatal.rawValue, error.code, error.description)
            return
        }
        
        XCTFail("An connect error not raised as expected")
    }
    
    // MARK: - Disconnect
    
    func testSessionDisconnect() {
        do {
            let session = try launchSessionWithAuthMethod(.PublicKey, user: userForSFA)
            XCTAssert(session.connected)
            XCTAssertFalse(session.disconnected)
            
            try disconnectSessionAndWait(session)
            XCTAssertFalse(session.connected)
            XCTAssert(session.disconnected)
        } catch let error as NSError {
            XCTFail(error.description)
        }
    }
    
    // MARK: - Trivial Properties
    
    func testTrivialProperties() {
        do {
            let session = try launchSessionWithAuthMethod(.PublicKey, user: userForSFA)
            XCTAssertEqual(session.host, sshHost)
            XCTAssertEqual(session.port, sshPort)
            XCTAssertEqual(session.username, userForSFA)
            XCTAssertGreaterThan(session.fd, -1)
        } catch let error as NSError {
            XCTFail(error.description)
        }
    }
    
    // MARK: - Authentication
    
    func testSessionConnectWithInvalidUser() {
        do {
            try launchSessionWithAuthMethods([.PublicKey, .Password, .Interactive], user: invalidUser)
        } catch let error as NSError {
            XCTAssertEqual(SSHKitErrorCode.RequestDenied.rawValue, error.code, error.description)
            return
        }
        
        XCTFail("An auth error not raised as expected")
    }
    
    func testSessionConnectWithInvalidPass() {
        let correctPassword = password
        password = "invalid-password"
        
        defer {
            // recover changed password for other tests
            password = correctPassword
        }
        
        do {
            try launchSessionWithAuthMethods([.PublicKey, .Password, .Interactive], user: userForSFA)
        } catch let error as NSError {
            XCTAssertEqual(SSHKitErrorCode.RequestDenied.rawValue, error.code, error.description)
            return
        }
        
        XCTFail("An auth error not raised as expected")
    }

    func testSessionSingleFactorAuth() {
        do {
            try launchSessionWithAuthMethod(.PublicKey, user: userForSFA)
            try launchSessionWithAuthMethod(.Password, user: userForSFA)
            try launchSessionWithAuthMethod(.Interactive, user: userForSFA)
        } catch let error as NSError {
            XCTFail(error.description)
        }
    }
    
    func testSessionMultiFactorAuth() {
        do {
            try launchSessionWithAuthMethods([.PublicKey, .Password, .Interactive], user: userForMFA)
        } catch let error as NSError {
            XCTFail(error.description)
        }
    }
    
    func testSessionAuthFail() {
        do {
            try launchSessionWithAuthMethods([.PublicKey, .Password, .Interactive], user: userForNoPass)
        } catch let error as NSError {
            XCTAssertEqual(SSHKitErrorCode.RequestDenied.rawValue, error.code, error.description)
            return
        }
        
        XCTFail("An auth error not raised as expected")
    }
}
