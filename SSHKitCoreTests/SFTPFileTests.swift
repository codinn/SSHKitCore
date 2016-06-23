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
    let filePathForWriteTest = "./test_write.txt"
    let filePathForReadTest = "./test_read.txt"

    // MARK: - setUp
    override func setUp() {
        super.setUp()
        
        mkdir(lsFolderPathForTest)
        createEmptyFile(lsFolderPathForTest.stringByAppendingString("/1"))
        createEmptyFile(lsFolderPathForTest.stringByAppendingString("/2"))
        
        unlink(filePathForWriteTest)
        unlink(filePathForReadTest)
    }
    
    override func tearDown() {
        // Put teardown code here. This method is called after the invocation of each test method in the class.
        super.tearDown()
        
        unlink(lsFolderPathForTest.stringByAppendingString("/1"))
        unlink(lsFolderPathForTest.stringByAppendingString("/2"))
        rmdir(lsFolderPathForTest)
    }
    
    // MARK: - helper function
    func createFile(filename: String, content: String) {
        
        do {
            let file = try channel?.openFileForWrite(filename, shouldResume: false, mode: 0o755)
            let length = content.lengthOfBytesUsingEncoding(NSUTF8StringEncoding)
            let data = content.cStringUsingEncoding(NSUTF8StringEncoding)
            let error: NSErrorPointer = nil
            let writeLength = file?.write(data!, size: length, errorPtr: error)
            XCTAssertEqual(length, writeLength)
            file?.close()
        } catch let error as NSError {
            XCTFail(error.description)
        }
    }

    // MARK: - test
    func testListDirectory() {
        do {
            var dir = try channel!.openDirectory(lsFolderPathForTest)
            var files = dir.listDirectory(nil)
            XCTAssertEqual(files.count, 4)
            dir.close()
            
            dir = try channel!.openDirectory(lsFolderPathForTest)
            files = dir.listDirectory({ (filename) -> SSHKitSFTPListDirFilterCode in
                if filename == "." {
                    return .Ignore;
                }
                return .Add;
            })
            XCTAssertEqual(files.count, 3)
            dir.close()
            
            dir = try channel!.openDirectory(lsFolderPathForTest)
            files = dir.listDirectory({ (filename) -> SSHKitSFTPListDirFilterCode in
                return .Cancel
            })
            XCTAssertEqual(files.count, 0)
            dir.close()
            
        } catch let error as NSError {
            XCTFail(error.description)
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
            let file = try channel?.openFile(filename)
            
            file?.asyncReadFile(0, readFileBlock: { (buffer, bufferLength) in
                //
                }, progressBlock: { (bytesNewReceived, bytesReceived, bytesTotal) in
                }, fileTransferSuccessBlock: { (file, startTime, finishTime, newFilePath) in
                    self.readFileExpectation?.fulfill()
                }, fileTransferFailBlock: { (error) in
                    XCTFail(error.description)
            })
            
            waitForExpectationsWithTimeout(5) { error in
                if let error=error {
                    XCTFail(error.description)
                }
            }
            
            file?.close()
        } catch let error as NSError {
            XCTFail(error.description)
        }
    }

}