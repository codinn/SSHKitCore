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

    func testOpenDirectory() {
        do {
            let session = try launchSessionWithAuthMethod(.PublicKey, user: userForSFA)
            let channel = try self.openSFTPChannel(session)
            XCTAssert(channel.isOpen)
            channel .openDirectory("./")
            session.disconnect()
        } catch let error as NSError {
            XCTFail(error.description)
        }
    }
    
    func testOpenFile() {
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
