//
//  DirectChannelTests.swift
//  SSHKitCore
//
//  Created by vicalloy on 2/21/16.
//
//

import XCTest

class DirectChannelTests: SessionTestCase, SSHKitChannelDelegate {
    private var openExpectation: XCTestExpectation?
    private var closeExpectation: XCTestExpectation?
    private var writeExpectation: XCTestExpectation?
    
    private var writeDataCount: Int = 0
    private let writeDataMaxTimes = 100
    private var totoalWroteDataLength: Int = -1
    
    private let dataWrote = NSMutableData()
    private let dataRead = NSMutableData()
    
    private let echoHost = "127.0.0.1"
    private let echoPort = 6007
    let echoServer = EchoServer(port: 6007)

    override func setUp() {
        super.setUp()
        echoServer.start()
    }
    
    override func tearDown() {
        echoServer.stop()
        super.tearDown()
    }
    
    // MARK: - Direct-TCPIP Channel
    
    func openDirectChannelWithTargetHost(host: String, port: Int) throws -> SSHKitDirectChannel {
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
    
    func testOpen() {
        do {
            let channel = try self.openDirectChannelWithTargetHost(echoHost, port: echoPort)
            XCTAssert(channel.isOpen)
            XCTAssertEqual(channel.targetHost, echoHost)
            XCTAssertEqual( Int(channel.targetPort), echoPort)
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
                dataWrote.appendData(data!)
            }
            
            waitForExpectationsWithTimeout(5) { error in
                if let error = error {
                    XCTFail(error.description)
                }
            }
            
            XCTAssertEqual(dataRead, dataWrote)
        } catch let error as NSError {
            XCTFail(error.description)
        }
    }
    
    func testClose() {
        do {
            let channel = try self.openDirectChannelWithTargetHost(echoHost, port: echoPort)
            XCTAssert(channel.isOpen)
            XCTAssertEqual(channel.targetHost, echoHost)
            XCTAssertEqual( Int(channel.targetPort), echoPort)
            
            closeExpectation = expectationWithDescription("Close direct channel")
            channel.close()
            waitForExpectationsWithTimeout(1) { error in
                if let error = error {
                    print("Error: \(error.localizedDescription)")
                }
            }
            XCTAssertFalse(channel.isOpen)
        } catch let error as NSError {
            XCTFail(error.localizedDescription)
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
        dataRead.appendData(data)
        
        if writeDataCount == writeDataMaxTimes && dataRead.length >= totoalWroteDataLength {
            writeExpectation!.fulfill()
        }
    }
    
    func channel(channel: SSHKitChannel, didReadStderrData data: NSData) {
        print("didReadStderrData")
    }

    func channelDidClose(channel: SSHKitChannel!, withError error: NSError!) {
        if let expectation = closeExpectation {
            expectation.fulfill()
        }
    }
}