//
//  SFTPChannelTests.swift
//  SSHKitCore
//
//  Created by vicalloy on 6/15/16.
//
//

import XCTest

class SFTPChannelTests: SFTPTests {
    // TODO add a script to reset sftp test env(file.txt,rename.txt,remove.txt,ls/1,ls/2)

    func testOpenDirectorySucc() {
        do {
            let dir = try channel!.openDirectory("./")
            dir.close()
        } catch let error as NSError {
            XCTFail(error.description)
        }
    }
    
    func testOpenDirectoryFail() {
        do {
            try channel!.openDirectory("./no_this_dir")
            XCTFail("open dir must fail, but succ")
        } catch let error as NSError {
            XCTAssertEqual(error.code, SSHKitSFTPErrorCode.NoSuchFile.rawValue)
        }
    }
    
    func testOpenFileSucc() {
        do {
            let file = try channel!.openFile("file.txt")
            file.close()
        } catch let error as NSError {
            XCTFail(error.description)
        }
    }
    
    func testOpenFileFail() {
        do {
            try channel!.openFile("./no_this_file")
            XCTFail("open file must fail, but succ")
        } catch let error as NSError {
            XCTAssertEqual(error.code, SSHKitSFTPErrorCode.EOF.rawValue)
        }
    }
    
    func testCanonicalizePath() {
        do {
            let newPath = try channel!.canonicalizePath("./")
            XCTAssertEqual(newPath, "/Users/sshtest")
        } catch let error as NSError {
            XCTFail(error.description)
        }
    }
    
    func testChmod() {
        let path = "./file.txt"
        let error = channel!.chmod(path, mode: 0o700)
        
        if let error=error {
            // TODO remove folder
            XCTFail(error.description)
        }
        
        do {
            let file = try channel!.openFile(path)
            XCTAssertEqual(file.posixPermissions, 0o100700)
        } catch let error as NSError {
            XCTFail(error.description)
        }
        
        channel!.chmod(path, mode: 0o755)
    }
    
    func testRename() {
        // TODO create folder
        let oldName = "./rename.txt"
        let newName = "./renamed.txt"
        var error = channel!.rename(oldName, newName: newName)
        
        if let error=error {
            XCTFail(error.description)
        }
        
        error = channel!.rename(newName, newName: oldName)
    }
    
    func testMkdir() {
        let path = "./newFolder"
        var error = channel!.mkdir(path, mode: 0o755)
        if let error=error {
            XCTFail(error.description)
        }
        error = channel!.mkdir(path, mode: 0o755)
        XCTAssertEqual(error.code, SSHKitSFTPErrorCode.FileAlreadyExists.rawValue)  // folder existed
        
        error = channel!.rmdir(path)
        if let error=error {
            XCTFail(error.description)
        }
    }
    
    func testRmdir() {
        // create folder
        let path = "./newFolder"
        var error = channel!.mkdir(path, mode: 0o755)
        if let error=error {
            XCTFail(error.description)
        }
        
        error = channel!.rmdir(path)
        if let error=error {
            XCTFail(error.description)
        }
        
        error = channel!.rmdir(path)
        XCTAssertEqual(error.code, SSHKitSFTPErrorCode.NoSuchFile.rawValue)
    }
    
    func testUnlik() {
        // TODO create file
        let path = "./remove.txt"
        var error = channel!.unlink(path)
        if let error=error {
            XCTFail(error.description)
        }
        
        error = channel!.unlink(path)
        XCTAssertEqual(error.code, SSHKitSFTPErrorCode.NoSuchFile.rawValue)  // folder existed
    }


}
