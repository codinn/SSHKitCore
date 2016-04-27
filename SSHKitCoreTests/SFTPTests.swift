//
//  SFTPTests.swift
//  SSHKitCore
//
//  Created by vicalloy on 3/19/16.
//
//

import XCTest

class SFTPTests: SessionTestCase, SSHKitChannelDelegate {
    private var openChannelExpectation: XCTestExpectation?
    
    override func setUp() {
        super.setUp()
    }
    
    override func tearDown() {
        super.tearDown()
    }
    
    func openSFTPChannel(session: SSHKitSession) -> SSHKitSFTPChannel {
        openChannelExpectation = expectationWithDescription("Open SFTP Channel")
        let channel = session.openSFTPChannel(self)
        waitForExpectationsWithTimeout(5) { error in
            if let error = error {
                print("Error: \(error.localizedDescription)")
            }
        }
        XCTAssert(channel.isOpen)
        return channel
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
}