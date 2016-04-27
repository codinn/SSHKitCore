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
    let writeDataMaxTimes = 100
    var totoalWroteDataLength: Int = -1
    var totoalReadLength: Int = 0

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
    
    func openDirectChannelWithTargetHost(host: String, port: UInt16) throws -> SSHKitChannel {
        let session = try self.launchSessionWithAuthMethod(.PublicKey, user: userForSFA)
        
        openExpectation = expectationWithDescription("Open Direct Channel")
        let channel = session.openDirectChannelWithTargetHost(host, port: UInt(port), delegate: self)
        
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
    
    func openForwardChannelWithSession(session: SSHKitSession) -> SSHKitChannel {
        openExpectation = expectationWithDescription("Open Forward Channel")
        let channel = session.openForwardChannel()
        waitForExpectationsWithTimeout(1) { error in
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
            let channel = try self.openDirectChannelWithTargetHost(echoHost, port: echoPort)
            XCTAssert(channel.isOpen)
        } catch let error as NSError {
            XCTFail(error.localizedDescription)
        }
    }

    // TODO: add test cases for connection to target is timed out or refused
//    func testOpenDirectChannelTimedOut() {
//        do {
//            let channel = try self.openDirectChannelWithTargetHost(nonRoutableIP, port: echoPort)
//            XCTAssertFalse(channel.isOpen)
//        } catch _ as NSError {
//            return
//        }
//        
//        XCTFail("Channel open operation should timed out")
//    }
    
    func testReadWrite() {
        do {
            let channel = try self.openDirectChannelWithTargetHost(echoHost, port: echoPort)
            XCTAssert(channel.isOpen)
            
            writeExpectation = expectationWithDescription("Channel write data")
            let data = "00000000123456789qwertyuiop]中文".dataUsingEncoding(NSUTF8StringEncoding)
            
            totoalWroteDataLength = (data?.length)! * writeDataMaxTimes
            for _ in 0..<writeDataMaxTimes {
                channel.writeData(data)
            }
            waitForExpectationsWithTimeout(5) { error in
                if let error = error {
                    print("Error: \(error.localizedDescription)")
                }
            }
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
    }
    
    func channel(channel: SSHKitChannel, didReadStdoutData data: NSData) {
        totoalReadLength += data.length
        
        if writeDataCount == writeDataMaxTimes && totoalReadLength == totoalWroteDataLength {
            writeExpectation!.fulfill()
        }
    }
    
    func channel(channel: SSHKitChannel, didReadStderrData data: NSData) {
        print("didReadStderrData")
    }

}