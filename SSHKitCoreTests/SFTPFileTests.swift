//
//  SFTPFileTests.swift
//  SSHKitCore
//
//  Created by vicalloy on 6/17/16.
//
//

import XCTest

class SFTPFileTests: SFTPTests {
    
    let lsFolderPathForTest = "./ls"
    let filePathForWriteTest = "./test_write.txt"

    override func setUp() {
        super.setUp()
        
        mkdir(lsFolderPathForTest)
        createEmptyFile(lsFolderPathForTest.stringByAppendingString("/1"))
        createEmptyFile(lsFolderPathForTest.stringByAppendingString("/2"))
        
        unlink(filePathForWriteTest)
    }
    
    override func tearDown() {
        // Put teardown code here. This method is called after the invocation of each test method in the class.
        super.tearDown()
        
        unlink(lsFolderPathForTest.stringByAppendingString("/1"))
        unlink(lsFolderPathForTest.stringByAppendingString("/2"))
        rmdir(lsFolderPathForTest)
    }

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
    
    func _testWrite() {
        let filename = filePathForWriteTest
        
        do {
            let file = try channel?.openFileForWrite(filename, shouldResume: false, mode: 0o755)
            // file?.write
            file?.close()
        } catch let error as NSError {
            if error.code != SSHKitSFTPErrorCode.FileAlreadyExists.rawValue {
                XCTFail(error.description)
            }
        }
    }
    
    func _testRead() {
        let filename = filePathForWriteTest
        // TODO create file
        
        do {
            let file = try channel?.openFile(filename)
            file?.asyncReadFile(0, readFileBlock: { (buffer, bufferLength) in
                //
                }, progressBlock: { (bytesNewReceived, bytesReceived, bytesTotal) in
                    //
                }, fileTransferSuccessBlock: { (file, startTime, finishTime, newFilePath) in
                    //
                }, fileTransferFailBlock: { (error) in
                    //
            })
            file?.close()
        } catch let error as NSError {
            if error.code != SSHKitSFTPErrorCode.FileAlreadyExists.rawValue {
                XCTFail(error.description)
            }
        }
    }

}
