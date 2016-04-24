//
//  ChannelConnectTests.swift
//  SSHKitCore
//
//  Created by vicalloy on 2/21/16.
//
//

import XCTest

class DirectChannelTests: ChannelTestCase {
    var writeDataCount: Int = 0
    var totoalDataLength: Int = -1
    var totoalReadLength: Int = -1

    override func setUp() {
        super.setUp()
        totoalReadLength = 0
        startEchoServer()
        waitEchoServerStart()
    }
    
    override func tearDown() {
        stopEchoServer()
        super.tearDown()
    }
    
    func testOpenDirectChannel() {
        do {
            let session = try self.launchSessionWithAuthMethod(.PublicKey, user: userForSFA)
            self.openDirectChannel(session)
            // FIXME: must disconnect session before dealloc.
            // if session is connected and have unclosed channel will get a error on dealloc
            session.disconnect()
        } catch let error as NSError {
            XCTFail(error.description)
        }
    }
    
    func testTunnel() {
        do {
            let session = try self.launchSessionWithAuthMethod(.PublicKey, user: userForSFA)
            let channel = self.openDirectChannel(session)
            channelExpectation = expectationWithDescription("Channel write data")
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
    
    // MARK: SSHKitChannelDelegate
    override func channelDidWriteData(channel: SSHKitChannel) {
        writeDataCount += 1
        // print("channelDidWriteData:\(writeDataCount)")
    }
    
    override func channel(channel: SSHKitChannel, didReadStdoutData data: NSData) {
        totoalReadLength += data.length
        if writeDataCount == 1000 && totoalReadLength == totoalDataLength {
            channelExpectation!.fulfill()
        }
    }
    
    override func channel(channel: SSHKitChannel, didReadStderrData data: NSData) {
        print("didReadStderrData")
    }

}