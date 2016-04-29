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
    private var openExpectation: XCTestExpectation?
    private var writeCmdExpectation: XCTestExpectation?
    private var readResultExpectation: XCTestExpectation?
    
    // let server prints its system name
    private let command = "uname -s\n"
    // for OS X, it should be "Darwin"
    private let sysName = "Darwin"
    
    private let stdoutData = NSMutableData()
    
    override func setUp() {
        super.setUp()
    }
    
    override func tearDown() {
        super.tearDown()
    }
    
    func openChannelWithSession(session: SSHKitSession) throws -> SSHKitShellChannel {
        openExpectation = expectationWithDescription("Open Shell Channel")
        let channel = session.openShellChannelWithTerminalType("xterm", columns: 20, rows: 50, delegate: self)
        waitForExpectationsWithTimeout(1) { error in
            if let error = error {
                self.error = error
            }
        }
        
        if let error = self.error {
            throw error
        }
        
        return channel
    }
    
    func testOpen() {
        do {
            let session = try self.launchSessionWithAuthMethod(.PublicKey, user: userForSFA)
            let channel = try self.openChannelWithSession(session)
            XCTAssert(channel.isOpen)
        } catch let error as NSError {
            XCTFail(error.description)
        }
    }
    
    func testChangePtySize() {
        do {
            let session = try self.launchSessionWithAuthMethod(.PublicKey, user: userForSFA)
            let channel = try self.openChannelWithSession(session)
            
            resizeExpectation = expectationWithDescription("Shell Channel Change Pty Size To Columns(")
            channel.changePtySizeToColumns(150, rows: 150)
            waitForExpectationsWithTimeout(1) { error in
                if let error = error {
                    self.error = error
                }
            }
            
            if let error = self.error {
                XCTFail(error.description)
            } else {
                XCTAssertEqual(channel.rows, 150)
                XCTAssertEqual(channel.columns, 150)
            }
        } catch let error as NSError {
            XCTFail(error.description)
        }
    }
    
    func testExecuteRemoteCommand() {
        do {
            let session = try self.launchSessionWithAuthMethod(.PublicKey, user: userForSFA)
            let channel = try self.openChannelWithSession(session)
            
            writeCmdExpectation = expectationWithDescription("Run remote command \(command)")
            readResultExpectation = expectationWithDescription("Read remote system name")
            
            let cmdData = (command as NSString).dataUsingEncoding(NSUTF8StringEncoding)
            
            channel.writeData(cmdData)
            waitForExpectationsWithTimeout(100) { error in
                if let error = error {
                    self.error = error
                }
            }
            
            if let error = self.error {
                XCTFail(error.description)
                return
            }
        } catch let error as NSError {
            XCTFail(error.description)
        }
    }
    
    // MARK: - SSHKitChannelDelegate
    
    func channel(channel: SSHKitChannel, didReadStdoutData data: NSData) {
        stdoutData.appendData(data)
        
        if let datastring = String(data: stdoutData, encoding: NSUTF8StringEncoding) {
            if datastring.containsString(sysName) {
                readResultExpectation?.fulfill()
                stdoutData.length = 0
            }
        }
    }
    
    func channel(channel: SSHKitChannel, didReadStderrData data: NSData) {
    }
    
    func channelDidWriteData(channel: SSHKitChannel) {
        writeCmdExpectation?.fulfill()
    }
    
    func channelDidClose(channel: SSHKitChannel, withError error: NSError) {
        self.error = error;
    }
    
    func channelDidOpen(channel: SSHKitChannel) {
        openExpectation?.fulfill()
    }
    
    // MARK: - SSHKitShellChannelDelegate
    
    func channel(channel: SSHKitShellChannel, didChangePtySizeToColumns columns: Int, rows: Int, withError error: NSError) {
        self.error = error
        resizeExpectation?.fulfill()
    }

}
