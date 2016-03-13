//
//  ChannelConnectTests.swift
//  SSHKitCore
//
//  Created by vicalloy on 2/21/16.
//
//

import XCTest

class ShellChannelTests: SSHKitCoreTestsBase {

    override func setUp() {
        super.setUp()
    }
    
    override func tearDown() {
        super.tearDown()
    }
    
    func testOpenShellChannel() {
        let session = self.connectSessionByPublicKeyBase64()
        self.openShellChannel(session)
        session.disconnect()
    }
    
    
    func testShellChangePtySizeToColumns() {
        let session = self.connectSessionByPublicKeyBase64()
        let channel = self.openShellChannel(session)
        expectation = expectationWithDescription("Shell Change Pty Size To Columns(")
        channel.changePtySizeToColumns(150, rows: 150)
        waitForExpectationsWithTimeout(5) { error in
            if let error = error {
                print("Error: \(error.localizedDescription)")
            }
        }
        // TODO XCTAssert()
        XCTAssertEqual(channel.rows, 150)
        XCTAssertEqual(channel.columns, 150)
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
    
    //MARK: SSHKitShellChannelDelegate
    override func channel(channel: SSHKitShellChannel, didChangePtySizeToColumns columns: Int, rows: Int, withError error: NSError) {
        expectation!.fulfill()
    }

}
