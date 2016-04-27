//
//  ChannelTestCase.swift
//  SSHKitCore
//
//  Created by Yang Yubo on 4/22/16.
//
//

import XCTest

class ChannelTestCase: SessionTestCase, SSHKitShellChannelDelegate {
    private var openChannelExpectation: XCTestExpectation?
    private var echoServerExpectation: XCTestExpectation?
    
    let echoTask = NSTask()
    let echoPort : UInt16 = 6007

    override func setUp() {
        super.setUp()
        // Put setup code here. This method is called before the invocation of each test method in the class.
    }
    
    override func tearDown() {
        super.tearDown()
    }
    
    // MARK: - Echo Server
    
    func startEchoServer() {
        let echoServer = NSBundle(forClass: self.dynamicType).pathForResource("echo_server.py", ofType: "");
        echoTask.launchPath = echoServer
        echoTask.arguments = ["-p", "\(echoPort)"]
        
        let pipe = NSPipe()
        echoTask.standardOutput = pipe
        echoTask.standardError = pipe
        echoTask.standardInput = NSFileHandle.fileHandleWithNullDevice()
        pipe.fileHandleForReading.readabilityHandler = { (handler: NSFileHandle?) in
            if let data = handler?.availableData {
                if let output = String(data: data, encoding: NSUTF8StringEncoding) {
                    print(output)
                }
            }
            
            self.echoServerExpectation?.fulfill()
            // stop catch output
            pipe.fileHandleForReading.readabilityHandler = nil;
        }
        
        echoTask.terminationHandler = { (task: NSTask) in
            // set readabilityHandler block to nil; otherwise, you'll encounter high CPU usage
            pipe.fileHandleForReading.readabilityHandler = nil;
        }
        
        echoTask.launch()
    }
    
    func stopEchoServer() {
        echoTask.terminate()
    }
    
    func waitEchoServerStart() {
        echoServerExpectation = expectationWithDescription("Wait echo server start")
        waitForExpectationsWithTimeout(5) { error in
            if let error = error {
                XCTFail(error.localizedDescription)
                self.stopEchoServer()
            }
        }
    }
    
    // MARK: - Open Channel
    
    func openDirectChannel(session: SSHKitSession) -> SSHKitChannel {
        openChannelExpectation = expectationWithDescription("Open Direct Channel")
        let channel = session.openDirectChannelWithTargetHost("127.0.0.1", port: UInt(echoPort), delegate: self)
        waitForExpectationsWithTimeout(5) { error in
            if let error = error {
                print("Error: \(error.localizedDescription)")
            }
        }
        XCTAssert(channel.isOpen)
        return channel
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
    
    func openForwardChannel(session: SSHKitSession) -> SSHKitChannel {
        openChannelExpectation = expectationWithDescription("Open Forward Channel")
        let channel = session.openForwardChannel()
        waitForExpectationsWithTimeout(5) { error in
            if let error = error {
                print("Error: \(error.localizedDescription)")
            }
        }
        XCTAssert(channel.isOpen)
        return channel
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
        // print("didChangePtySizeToColumns")
    }
}
