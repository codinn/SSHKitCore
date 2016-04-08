//
//  ConnectTests.swift
//  SSHKitCore
//
//  Created by vicalloy on 2/21/16.
//
//

import XCTest

class SessionTests: SSHTestsBase {

    override func setUp() {
        super.setUp()
        // Put setup code here. This method is called before the invocation of each test method in the class.
    }
    
    override func tearDown() {
        // Put teardown code here. This method is called after the invocation of each test method in the class.
        super.tearDown()
    }

    func testConnectSessionByPublicKeyBase64() {
        self.connectSessionByPublicKeyBase64()
    }
    
    func testConnectSessionByPassword() {
        self.connectSessionByPassword()
    }
    
    func testConnectSessionByKeyboardInteractive() {
        self.connectSessionByKeyboardInteractive()
    }

}
