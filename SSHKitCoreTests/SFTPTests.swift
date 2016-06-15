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
    
    func openSFTPChannel(session: SSHKitSession) throws -> SSHKitSFTPChannel {
        openChannelExpectation = expectationWithDescription("Open SFTP Channel")
        let channel = session.openSFTPChannel(self)
        
        waitForExpectationsWithTimeout(5) { error in
            if let error = error {
                self.error = error
            }
        }
        
        if let error = self.error {
            throw error
        }

        return channel
    }
    
    func testOpenSFTPChannel() {
        do {
            let session = try launchSessionWithAuthMethod(.PublicKey, user: userForSFA)
            let channel = try self.openSFTPChannel(session)
            XCTAssert(channel.isOpen)
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