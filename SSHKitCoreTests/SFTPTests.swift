//
//  SFTPTests.swift
//  SSHKitCore
//
//  Created by vicalloy on 3/19/16.
//
//

import XCTest

class SFTPTests: SSHTestsBase {

    override func setUp() {
        super.setUp()
    }
    
    override func tearDown() {
        super.tearDown()
    }
    
    func testOpenSFTPChannel() {
        let session = self.launchSessionWithAuthMethod(.PublicKey)
        self.openSFTPChannel(session)
        session.disconnect()
    }
    
    
    // MARK: SSHKitChannelDelegate
    override func channelDidWriteData(channel: SSHKitChannel) {
        // print("channelDidWriteData:\(writeDataCount)")
    }
    
    override func channel(channel: SSHKitChannel, didReadStdoutData data: NSData) {
    }
    
    override func channel(channel: SSHKitChannel, didReadStderrData data: NSData) {
        print("didReadStderrData")
    }
    
}