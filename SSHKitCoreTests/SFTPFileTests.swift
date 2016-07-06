//
//  SFTPFileTests.swift
//  SSHKitCore
//
//  Created by vicalloy on 6/17/16.
//
//

import XCTest

class SFTPFileTests: SFTPTests {
    
    private var readFileExpectation: XCTestExpectation?

    let lsFolderPathForTest = "./ls"
    let lnFolderPathForTest = "./ln"
    let lnFilePathForTest = "./lnFile"
    let filePathForWriteTest = "./test_write.txt"
    let filePathForReadTest = "./test_read.txt"

    // MARK: - setUp
    override func setUp() {
        super.setUp()
        
        mkdir(lsFolderPathForTest)
        createEmptyFile(lsFolderPathForTest.stringByAppendingString("/1"))
        createEmptyFile(lsFolderPathForTest.stringByAppendingString("/2"))
        channel!.symlink(lsFolderPathForTest, destination: lnFolderPathForTest)
        channel!.symlink(lsFolderPathForTest.stringByAppendingString("/1"), destination: lnFilePathForTest)
        
        unlink(filePathForWriteTest)
        unlink(filePathForReadTest)
    }
    
    override func tearDown() {
        // Put teardown code here. This method is called after the invocation of each test method in the class.
        unlink(lsFolderPathForTest.stringByAppendingString("/1"))
        unlink(lsFolderPathForTest.stringByAppendingString("/2"))
        unlink(lnFolderPathForTest)
        unlink(lnFilePathForTest)
        rmdir(lsFolderPathForTest)
        
        unlink(filePathForWriteTest)
        unlink(filePathForReadTest)
        
        super.tearDown()
    }
    
    // MARK: - helper function
    func createFile(filename: String, content: String) {
        
        do {
            let file = try SSHKitSFTPFile.openFileForWrite(channel, path: filename, shouldResume: false, mode: 0o755)
            let length = content.lengthOfBytesUsingEncoding(NSUTF8StringEncoding)
            let data = content.cStringUsingEncoding(NSUTF8StringEncoding)
            let error: NSErrorPointer = nil
            let writeLength = file.write(data!, size: length, errorPtr: error)
            XCTAssertEqual(length, writeLength)
            file.close()
        } catch let error as NSError {
            XCTFail(error.description)
        }
    }

    // MARK: - test
    func testListDirectory() {
        do {
            var dir = try SSHKitSFTPFile.openDirectory(channel, path: lsFolderPathForTest)
            var files = dir.listDirectory(nil)
            XCTAssertEqual(files.count, 4)
            dir.close()
            
            dir = try SSHKitSFTPFile.openDirectory(channel, path: lsFolderPathForTest)
            files = dir.listDirectory({ (filename) -> SSHKitSFTPListDirFilterCode in
                if filename == "." {
                    return .Ignore;
                }
                return .Add;
            })
            XCTAssertEqual(files.count, 3)
            dir.close()
            
            dir = try SSHKitSFTPFile.openDirectory(channel, path: lsFolderPathForTest)
            files = dir.listDirectory({ (filename) -> SSHKitSFTPListDirFilterCode in
                return .Cancel
            })
            XCTAssertEqual(files.count, 0)
            dir.close()
            
            // test symlink
            dir = try SSHKitSFTPFile.openDirectory(channel, path: lnFolderPathForTest)
            files = dir.listDirectory(nil)
            XCTAssertEqual(files.count, 4)
            dir.close()
            
        } catch let error as NSError {
            XCTFail(error.description)
        }
        do {
            // try to ls symlink file
            let dir = try SSHKitSFTPFile.openDirectory(channel, path: lnFilePathForTest)
            let files = dir.listDirectory(nil)
            XCTAssertEqual(files.count, 4)
            dir.close()
        } catch let error as NSError {
            if error.code != SSHKitSFTPErrorCode.NoSuchFile.rawValue {
                XCTFail(error.description)
            }
        }
    }
    
    func testWrite() {
        let filename = filePathForWriteTest
        
        var i = 0
        var content = "0123456789abcd"
        while i < 10 {
            content = content.stringByAppendingString(content)
            i += 1
        }
        
        createFile(filename, content: content)
    }
    
    func testRead() {
        let filename = filePathForReadTest
        
        var i = 0
        var content = "0123456789abcd"
        while i < 10 {
            content = content.stringByAppendingString(content)
            i += 1
        }
        // let totalLength = content.lengthOfBytesUsingEncoding(NSUTF8StringEncoding)
        
        createFile(filename, content: content)
        
        do {
            readFileExpectation = expectationWithDescription("Read File Success")
            let file = try SSHKitSFTPFile.openFile(channel, path: filename)
            
            file.asyncReadFile(0, readFileBlock: { (buffer, bufferLength) in
                //
                }, progressBlock: { (bytesNewReceived, bytesReceived, bytesTotal) in
                }, fileTransferSuccessBlock: {
                    self.readFileExpectation?.fulfill()
                }, fileTransferFailBlock: { (error) in
                    XCTFail(error.description)
            })
            
            waitForExpectationsWithTimeout(5) { error in
                if let error=error {
                    XCTFail(error.description)
                }
            }
            
            file.close()
        } catch let error as NSError {
            XCTFail(error.description)
        }
    }

}
