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
    let filePathForTest = "./file.txt"
    let folderPathForTest = "./folder"
    let symlinkFolderPathForTest = "./symlink"
    let newSymlinkFolderPathForTest = "./newSymlink"
    let newFolderPathForTest = "./newFolder"
    
    // MARK: - setUp
    override func setUp() {
        super.setUp()
        
        createEmptyFile(filePathForTest)
        
        mkdir(folderPathForTest)
        rmdir(newFolderPathForTest)
        
        unlink(newSymlinkFolderPathForTest)
        channel!.symlink(folderPathForTest, destination: symlinkFolderPathForTest)
    }
    
    override func tearDown() {
        // Put teardown code here. This method is called after the invocation of each test method in the class.
        super.tearDown()
        unlink(filePathForTest)
        rmdir(folderPathForTest)
    }
    
    // MARK: - test
    func testUnlik() {
        let path = filePathForTest
        var error = channel!.unlink(path)
        
        if let error=error {
            XCTFail(error.description)
        }
        
        error = channel!.unlink(path)
        XCTAssertEqual(error.code, SSHKitSFTPErrorCode.NoSuchFile.rawValue)  // folder existed
    }

    func testOpenDirectorySucc() {
        do {
            let dir = try SSHKitSFTPFile.openDirectory(channel, path: "./")
            dir.close()
        } catch let error as NSError {
            XCTFail(error.description)
        }
    }
    
    func testOpenDirectoryFail() {
        do {
            try SSHKitSFTPFile.openDirectory(channel, path: "./no_this_dir")
            XCTFail("open dir must fail, but succ")
        } catch let error as NSError {
            XCTAssertEqual(error.code, SSHKitSFTPErrorCode.NoSuchFile.rawValue)
        }
    }
    
    func testOpenFileSucc() {
        do {
            let file = try SSHKitSFTPFile.openFile(channel, path: filePathForTest)
            file.close()
        } catch let error as NSError {
            XCTFail(error.description)
        }
    }
    
    func testOpenFileFail() {
        do {
            try SSHKitSFTPFile.openFile(channel, path: "./no_this_file")
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
        let path = filePathForTest
        let error = channel!.chmod(path, mode: 0o700)
        
        if let error=error {
            XCTFail(error.description)
        }
        
        do {
            let file = try SSHKitSFTPFile.openFile(channel, path: path)
            XCTAssertEqual(file.posixPermissions, 0o100700)
        } catch let error as NSError {
            XCTFail(error.description)
        }
        
        channel!.chmod(path, mode: 0o755)
    }
    
    func testRename() {
        let oldName = filePathForTest
        let newName = "./renamed.txt"
        let error = channel!.rename(oldName, newName: newName)
        
        if let error=error {
            XCTFail(error.description)
        }
        
        unlink(newName)  // clean test file
    }
    
    func testMkdir() {
        let path = newFolderPathForTest
        
        var error = channel!.mkdir(path, mode: 0o755)
        if let error=error {
            XCTFail(error.description)
        }
        
        error = channel!.mkdir(path, mode: 0o755)
        XCTAssertEqual(error.code, SSHKitSFTPErrorCode.FileAlreadyExists.rawValue)  // folder existed
    }
    
    func testRmdir() {
        let path = folderPathForTest
        var error = channel!.rmdir(path)

        if let error=error {
            XCTFail(error.description)
        }
        
        error = channel!.rmdir(path)
        XCTAssertEqual(error.code, SSHKitSFTPErrorCode.NoSuchFile.rawValue)
    }
    
    func testSymlink() {
        let targetPath = folderPathForTest
        let destination = newSymlinkFolderPathForTest
        
        var error = channel!.symlink(targetPath, destination: destination)
        if let error=error {
            XCTFail(error.description)
        }
        
        error = channel!.symlink(targetPath, destination: destination)
        XCTAssertEqual(error.code, SSHKitSFTPErrorCode.GenericFailure.rawValue)
    }
    
    func testReadlink() {
        let path = symlinkFolderPathForTest
        do {
            let destination = try channel!.readlink(path)
            XCTAssertEqual(destination, folderPathForTest)
        } catch let error as NSError {
            XCTFail(error.description)
        }
        do {
            try channel!.readlink("./no_this_link")
            XCTFail("readk link must fail, but succ")
        } catch let error as NSError {
            XCTAssertEqual(error.code, SSHKitSFTPErrorCode.GenericFailure.rawValue)
        }
    }

}
