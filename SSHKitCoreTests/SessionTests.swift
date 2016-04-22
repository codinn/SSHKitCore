//
//  ConnectTests.swift
//  SSHKitCore
//
//  Created by vicalloy on 2/21/16.
//
//

import XCTest

class SessionTests: BasicSessionDelegate {

    override func setUp() {
        super.setUp()
        // Put setup code here. This method is called before the invocation of each test method in the class.
    }
    
    override func tearDown() {
        // Put teardown code here. This method is called after the invocation of each test method in the class.
        super.tearDown()
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
