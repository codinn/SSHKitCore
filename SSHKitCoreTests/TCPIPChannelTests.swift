//
//  TCPIPChannelTests.swift
//  SSHKitCore
//
//  Created by vicalloy on 2/21/16.
//
//

import XCTest

class TCPIPChannelTests: SessionTestCase, SSHKitChannelDelegate {
    private var openExpectation: XCTestExpectation?
    private var writeExpectation: XCTestExpectation?
    
    let echoTask = NSTask()
    let echoHost = "127.0.0.1"
    let echoPort : UInt16 = 6007
    
    var writeDataCount: Int = 0
    var totoalDataLength: Int = -1
    var totoalReadLength: Int = -1

    override func setUp() {
        super.setUp()
        totoalReadLength = 0
        startEchoServer()
    }
    
    override func tearDown() {
        stopEchoServer()
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
        
        let echoServerExpectation = expectationWithDescription("Wait echo server start")
        pipe.fileHandleForReading.readabilityHandler = { (handler: NSFileHandle?) in
            if let data = handler?.availableData {
                if let output = String(data: data, encoding: NSUTF8StringEncoding) {
                    print(output)
                }
            }
            
            echoServerExpectation.fulfill()
            // stop catch output
            pipe.fileHandleForReading.readabilityHandler = nil;
        }
        
        echoTask.terminationHandler = { (task: NSTask) in
            // set readabilityHandler block to nil; otherwise, you'll encounter high CPU usage
            pipe.fileHandleForReading.readabilityHandler = nil;
        }
        
        echoTask.launch()
        
        waitForExpectationsWithTimeout(5) { error in
            if let error = error {
                XCTFail(error.localizedDescription)
                self.stopEchoServer()
            }
        }
    }
    
    func stopEchoServer() {
        echoTask.terminate()
    }
    
    // MARK: - Open Channel
    
    func openDirectChannelFromSession(session: SSHKitSession) -> SSHKitChannel {
        openExpectation = expectationWithDescription("Open Direct Channel")
        let channel = session.openDirectChannelWithTargetHost(targetHost, port: UInt(echoPort), delegate: self)
        waitForExpectationsWithTimeout(5) { error in
            if let error = error {
                print("Error: \(error.localizedDescription)")
            }
        }
        XCTAssert(channel.isOpen)
        return channel
    }
    
    func openForwardChannelFromSession(session: SSHKitSession) -> SSHKitChannel {
        openExpectation = expectationWithDescription("Open Forward Channel")
        let channel = session.openForwardChannel()
        waitForExpectationsWithTimeout(5) { error in
            if let error = error {
                print("Error: \(error.localizedDescription)")
            }
        }
        XCTAssert(channel.isOpen)
        return channel
    }
    
    // MARK: - Direct-TCPIP Channel
    
    func testOpenDirectChannel() {
        do {
            let session = try self.launchSessionWithAuthMethod(.PublicKey, user: userForSFA)
            self.openDirectChannelFromSession(session)
        } catch let error as NSError {
            XCTFail(error.description)
        }
    }
    
    func testTunnel() {
        do {
            let session = try self.launchSessionWithAuthMethod(.PublicKey, user: userForSFA)
            let channel = self.openDirectChannelFromSession(session)
            writeExpectation = expectationWithDescription("Channel write data")
            let data = "00000000123456789qwertyuiop]中文".dataUsingEncoding(NSUTF8StringEncoding)
            // NOTE: if 0..999 will fail(too many data?)
            totoalDataLength = (data?.length)! * 1000
            for _ in 0...999 {
                channel.writeData(data)
            }
            waitForExpectationsWithTimeout(5) { error in
                if let error = error {
                    print("Error: \(error.localizedDescription)")
                }
            }
            // TODO XCTAssert()
            session.disconnect()
        } catch let error as NSError {
            XCTFail(error.description)
        }
    }
    
    // MARK: - SSHKitChannelDelegate
    
    func channelDidOpen(channel: SSHKitChannel) {
        openExpectation!.fulfill()
    }
    
    func channelDidWriteData(channel: SSHKitChannel) {
        writeDataCount += 1
        // print("channelDidWriteData:\(writeDataCount)")
    }
    
    func channel(channel: SSHKitChannel, didReadStdoutData data: NSData) {
        totoalReadLength += data.length
        if writeDataCount == 1000 && totoalReadLength == totoalDataLength {
            writeExpectation!.fulfill()
        }
    }
    
    func channel(channel: SSHKitChannel, didReadStderrData data: NSData) {
        print("didReadStderrData")
    }

}