//
//  ChannelConnectTests.swift
//  SSHKitCore
//
//  Created by vicalloy on 2/21/16.
//
//

import XCTest

class ShellChannelTests: BasicSessionChannelDelegate {

    override func setUp() {
        super.setUp()
    }
    
    override func tearDown() {
        super.tearDown()
    }
    
    func testOpenShellChannel() {
        do {
            let session = try self.launchSessionWithAuthMethod(.PublicKey, user: userForSFA)
            self.openShellChannel(session)
            session.disconnect()
        } catch let error as NSError {
            XCTFail(error.description)
        }
    }
    
    
    func testShellChangePtySizeToColumns() {
        do {
            let session = try self.launchSessionWithAuthMethod(.PublicKey, user: userForSFA)
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
    
    //MARK: SSHKitShellChannelDelegate
    override func channel(channel: SSHKitShellChannel, didChangePtySizeToColumns columns: Int, rows: Int, withError error: NSError) {
        expectation!.fulfill()
    }

}
