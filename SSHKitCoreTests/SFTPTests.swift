//
//  SFTPTests.swift
//  SSHKitCore
//
//  Created by vicalloy on 3/19/16.
//
//

import XCTest

class SFTPTests: BasicSessionChannelDelegate {

    override func setUp() {
        super.setUp()
    }
    
    override func tearDown() {
        super.tearDown()
    }
    
    func testOpenSFTPChannel() {
        do {
            let session = try launchSessionWithAuthMethod(.PublicKey, user: userForSFA)
            self.openSFTPChannel(session)
            session.disconnect()
        } catch let error as NSError {
            XCTFail(error.description)
        }
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