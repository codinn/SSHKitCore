//
//  SFTPChannelTests.swift
//  SSHKitCore
//
//  Created by vicalloy on 6/15/16.
//
//

import XCTest

class SFTPChannelTests: SFTPTests {

    /*
 - (SSHKitSFTPFile *)openDirectory:(NSString *)path;
 - (SSHKitSFTPFile *)openFile:(NSString *)path;
 - (SSHKitSFTPFile *)openFile:(NSString *)path accessType:(int)accessType mode:(unsigned long)mode;
 - (SSHKitSFTPFile *)openFileForWrite:(NSString *)path shouldResume:(BOOL)shouldResume mode:(unsigned long)mode;
 - (NSString *)canonicalizePath:(NSString *)path;
 - (int)chmod:(NSString *)filePath mode:(unsigned long)mode;
 - (int)rename:(NSString *)original newName:(NSString *)newName;
 - (int)mkdir:(NSString *)directoryPath mode:(unsigned long)mode;
 - (int)rmdir:(NSString *)directoryPath;
 - (int)unlink:(NSString *)filePath;
*/
    
    override func setUp() {
        super.setUp()
        // Put setup code here. This method is called before the invocation of each test method in the class.
    }
    
    override func tearDown() {
        // Put teardown code here. This method is called after the invocation of each test method in the class.
        super.tearDown()
    }

    func testOpenDirectorySucc() {
        // try succ
        do {
            let session = try launchSessionWithAuthMethod(.PublicKey, user: userForSFA)
            let channel = try self.openSFTPChannel(session)
            defer {
                channel.close()
                session.disconnect()
            }
            XCTAssert(channel.isOpen)
            let dir = try channel.openDirectory("./")
            dir.close()
        } catch let error as NSError {
            XCTFail(error.description)
        }
    }
    
    func testOpenDirectoryFail() {
        // try fail
        do {
            let session = try launchSessionWithAuthMethod(.PublicKey, user: userForSFA)
            let channel = try self.openSFTPChannel(session)
            defer {
                channel.close();
                session.disconnect()
            }
            XCTAssert(channel.isOpen)
            try channel.openDirectory("./xxxx")
            XCTFail("open dir must fail, but succ")
        } catch _ as NSError {
            return
        }
    }
    
    func testOpenFileSucc() {
        // try succ
        do {
            let session = try launchSessionWithAuthMethod(.PublicKey, user: userForSFA)
            let channel = try self.openSFTPChannel(session)
            defer {
                channel.close()
                session.disconnect()
            }
            XCTAssert(channel.isOpen)
            let file = try channel.openFile("a.txt")
            file.close()
        } catch let error as NSError {
            XCTFail(error.description)
        }
    }
    
    func testOpenFileFail() {
        // try fail
        do {
            let session = try launchSessionWithAuthMethod(.PublicKey, user: userForSFA)
            let channel = try self.openSFTPChannel(session)
            defer {
                channel.close()
                session.disconnect()
            }
            XCTAssert(channel.isOpen)
            try channel.openFile("./xxxx")
            XCTFail("open file must fail, but succ")
        } catch _ as NSError {
            return
        }
    }
    
    func testCanonicalizePath() {
    }
    
    func testChmod() {
    }
    
    func testRename() {
    }
    
    func testMkdir() {
    }
    
    func testUnlik() {
    }


}
