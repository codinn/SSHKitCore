//
//  ChannelConnectTests.swift
//  SSHKitCore
//
//  Created by vicalloy on 2/21/16.
//
//

import XCTest

class DirectChannelTests: SSHTestsBase {
    
    var writeDataCount: Int = 0
    var totoalDataLength: Int = -1
    var totoalReadLength: Int = -1

    override func setUp() {
        startEchoServer()
        super.setUp()
        totoalReadLength = 0
        // Put setup code here. This method is called before the invocation of each test method in the class.
    }
    
    override func tearDown() {
        // Put teardown code here. This method is called after the invocation of each test method in the class.
        super.tearDown()
        stopEchoServer()
    }
    
    func testOpenDirectChannel() {
        let session = self.connectSessionByPublicKeyBase64()
        self.openDirectChannel(session)
        // FIXME: must disconnect session before dealloc.
        // if session is connected and have unclosed channel will get a error on dealloc
        session.disconnect()
    }
    
    func testTunnel() {
        let session = self.connectSessionByPublicKeyBase64()
        let channel = self.openDirectChannel(session)
        expectation = expectationWithDescription("Channel write data")
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
    }
    
    // MARK: SSHKitChannelDelegate
    override func channelDidWriteData(channel: SSHKitChannel) {
        writeDataCount += 1
        // print("channelDidWriteData:\(writeDataCount)")
    }
    
    override func channel(channel: SSHKitChannel, didReadStdoutData data: NSData) {
        totoalReadLength += data.length
        if writeDataCount == 1000 && totoalReadLength == totoalDataLength {
            expectation!.fulfill()
        }
    }
    
    override func channel(channel: SSHKitChannel, didReadStderrData data: NSData) {
        print("didReadStderrData")
    }

}