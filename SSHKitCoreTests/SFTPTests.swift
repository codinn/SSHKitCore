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
    var session: SSHKitSession?
    var channel: SSHKitSFTPChannel?
    
    // MARK: - setUp
    
    override func setUp() {
        super.setUp()
        do {
            let session = try launchSessionWithAuthMethod(.PublicKey, user: userForSFA)
            let channel = try self.openSFTPChannel(session)
            
            XCTAssert(channel.isOpen)
            
            self.session = session
            self.channel = channel
        } catch let error as NSError {
            XCTFail(error.description)
        }
        // Put setup code here. This method is called before the invocation of each test method in the class.
    }
    
    override func tearDown() {
        // Put teardown code here. This method is called after the invocation of each test method in the class.
        super.tearDown()
        /*
         if let session=self.session {
         session.disconnect()
         }
         */
        // FIXME session.disconnect() may fail. error at ssh_channel_free(ssh_channel channel)
    }
    
    // MARK: - helper function
    func createEmptyFile(filename: String) {
        do {
            let file = try SSHKitSFTPFile.openFileForWrite(channel, path: filename, shouldResume: false, mode: 0o755)
            file.close()
        } catch let error as NSError {
            if error.code != SSHKitSFTPErrorCode.FileAlreadyExists.rawValue {
                XCTFail(error.description)
            }
        }
    }
    
    func unlink(path: String) {
        let error = channel!.unlink(path)
        if let error=error {
            if error.code != SSHKitSFTPErrorCode.NoSuchFile.rawValue {
            }
        }
    }
    
    func rmdir(path: String) {
        let error = channel!.rmdir(path)
        if let error=error {
            if error.code != SSHKitSFTPErrorCode.NoSuchFile.rawValue {
                XCTFail(error.description)
            }
        }
    }
    
    func mkdir(path: String) {
        let error = channel!.mkdir(path, mode: 0o755)
        
        if let error=error {
            if error.code != SSHKitSFTPErrorCode.FileAlreadyExists.rawValue {
                XCTFail(error.description)
            }
        }
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
    
    // MARK: - test
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