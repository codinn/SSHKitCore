//
//  ChannelConnectTests.swift
//  SSHKitCore
//
//  Created by vicalloy on 2/21/16.
//
//

import XCTest

class ShellChannelTests: SessionTestCase, SSHKitShellChannelDelegate {
    private var resizeExpectation: XCTestExpectation?
    private var openChannelExpectation: XCTestExpectation?
    
    override func setUp() {
        super.setUp()
    }
    
    override func tearDown() {
        super.tearDown()
    }
    
    func openShellChannel(session: SSHKitSession) -> SSHKitShellChannel {
        openChannelExpectation = expectationWithDescription("Open Shell Channel")
        let channel = session.openShellChannelWithTerminalType("xterm", columns: 20, rows: 50, delegate: self)
        waitForExpectationsWithTimeout(5) { error in
            if let error = error {
                print("Error: \(error.localizedDescription)")
            }
        }
        XCTAssert(channel.isOpen)
        return channel
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
            resizeExpectation = expectationWithDescription("Shell Change Pty Size To Columns(")
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
    
    
    // MARK: - SSHKitChannelDelegate
    
    func channel(channel: SSHKitChannel, didReadStdoutData data: NSData) {
    }
    
    func channel(channel: SSHKitChannel, didReadStderrData data: NSData) {
    }
    
    func channelDidWriteData(channel: SSHKitChannel) {
    }
    
    func channelDidClose(channel: SSHKitChannel, withError error: NSError) {
        self.error = error;
    }
    
    func channelDidOpen(channel: SSHKitChannel) {
        openChannelExpectation!.fulfill()
    }
    
    // MARK: - SSHKitShellChannelDelegate
    
    func channel(channel: SSHKitShellChannel, didChangePtySizeToColumns columns: Int, rows: Int, withError error: NSError) {
        resizeExpectation!.fulfill()
    }

}
