//
//  ForwardChannelTests.swift
//  SSHKitCore
//
//  Created by Yang Yubo on 4/28/16.
//
//

import XCTest
import SwiftSockets

class ForwardChannelTests: SessionTestCase, SSHKitChannelDelegate {
    private var openExpectation: XCTestExpectation?
    private var closeExpectation: XCTestExpectation?
    private var writeExpectation: XCTestExpectation?
    
    private let listenHost = "127.0.0.1"
    private let listenPort = 6008
    
    private var writeDataCount: Int = 0
    private let writeDataMaxTimes = 100
    private var totoalWroteDataLength: Int = -1
    
    private let dataWrote = NSMutableData()
    private let dataRead = NSMutableData()
    
    private var forwardChannel: SSHKitForwardChannel?

    override func setUp() {
        super.setUp()
        // Put setup code here. This method is called before the invocation of each test method in the class.
    }
    
    override func tearDown() {
        // Put teardown code here. This method is called after the invocation of each test method in the class.
        super.tearDown()
    }
    
    // MARK: - TCPIP-Forward Channel
    
    func requestListeningOnAddress(host: String, port: Int) throws -> (SSHKitSession, Int) {
        let session = try self.launchSessionWithAuthMethod(.PublicKey, user: userForSFA)
        let requestExpectation = expectationWithDescription("Request listening on remote")
        
        var resultPort = 0
        
        session.requestListeningOnAddress(host, port: UInt16(port)) { (success, boundPort, error) in
            if error != nil {
                self.error = error
            }
            
            resultPort = Int(boundPort)
            requestExpectation.fulfill()
        }
        
        waitForExpectationsWithTimeout(1) { error in
            if let error = error {
                self.error = error
            }
        }
        
        if let error = self.error {
            throw error
        }
        
        return (session, resultPort)
    }
    
    func openWithListenHost(host: String, port: Int) throws -> (session: SSHKitSession, channel: SSHKitForwardChannel, clientSocket: ActiveSocketIPv4) {
        let (session, resultPort) = try requestListeningOnAddress(host, port: port)
        XCTAssertEqual(port, resultPort)
        
        openExpectation = expectationWithDescription("Open Forward Channel")
        
        // connect to opened port
        let remoteBoundAddress = sockaddr_in(address:host, port:port)
        let sendBackClient = ActiveSocketIPv4()!
        
        sendBackClient.connect(remoteBoundAddress) { socket in
        }
        
        waitForExpectationsWithTimeout(1) { error in
            if let error = error {
                self.error = error
            }
        }
        
        if let error = self.error {
            throw error
        }
        
        return (session, forwardChannel!, sendBackClient)
    }
    
    func testRequestRemoteListening() {
        do {
            let (session, resultPort) = try self.requestListeningOnAddress(listenHost, port: listenPort)
            XCTAssertEqual(listenPort, resultPort)
            try disconnectSessionAndWait(session)
        } catch let error as NSError {
            XCTFail(error.localizedDescription)
        }
    }
    
    func testReadWrite() {
        do {
            let (session, channel, client) = try openWithListenHost(listenHost, port: listenPort)
            XCTAssert(channel.isOpen)
            
            // receive data then just echo back
            client.onRead({ (sock, _) in
                let (count, data, errno) = sock.read()
                guard count > 0 else {
                    print("EOF, or great error handling \(errno).")
                    return
                }
                
                sock.asyncWrite(data, length: count)
            })
            
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
            try disconnectSessionAndWait(session)
        } catch let error as NSError {
            XCTFail(error.description)
        }
    }
    
    func testClose() {
        do {
            let (session, channel, _) = try openWithListenHost(listenHost, port: listenPort)
            XCTAssert(channel.isOpen)
            
            closeExpectation = expectationWithDescription("Close forward channel")
            channel.close()
            
            waitForExpectationsWithTimeout(1) { error in
                if let error = error {
                    print("Error: \(error.localizedDescription)")
                }
            }
            XCTAssertFalse(channel.isOpen)
            try disconnectSessionAndWait(session)
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
        
        if writeDataCount == writeDataMaxTimes && dataRead.length == totoalWroteDataLength {
            writeExpectation!.fulfill()
        }
    }
    
    func channel(channel: SSHKitChannel, didReadStderrData data: NSData) {
        XCTFail("Should never reach here")
    }
    
    func channelDidClose(channel: SSHKitChannel!, withError error: NSError!) {
        if let expectation = closeExpectation {
            expectation.fulfill()
        }
    }
    
    // MARK: - SSHKitSessionDelegate
    
    func session(session: SSHKitSession!, didOpenForwardChannel channel: SSHKitForwardChannel!) {
        channel.delegate = self;
        forwardChannel = channel
        openExpectation!.fulfill()
    }

}
