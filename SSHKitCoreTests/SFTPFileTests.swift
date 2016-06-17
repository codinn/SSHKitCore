//
//  SFTPFileTests.swift
//  SSHKitCore
//
//  Created by vicalloy on 6/17/16.
//
//

import XCTest

class SFTPFileTests: SFTPTests {

    override func setUp() {
        super.setUp()
        // Put setup code here. This method is called before the invocation of each test method in the class.
    }
    
    override func tearDown() {
        // Put teardown code here. This method is called after the invocation of each test method in the class.
        super.tearDown()
    }

    func testListDirectory() {
        do {
            var dir = try channel!.openDirectory("./ls")
            var files = dir.listDirectory(nil)
            XCTAssertEqual(files.count, 4)
            dir.close()
            
            dir = try channel!.openDirectory("./ls")
            files = dir.listDirectory({ (filename) -> SSHKitSFTPListDirFilterCode in
                if filename == "." {
                    return .Ignore;
                }
                return .Add;
            })
            XCTAssertEqual(files.count, 3)
            dir.close()
            
            dir = try channel!.openDirectory("./ls")
            files = dir.listDirectory({ (filename) -> SSHKitSFTPListDirFilterCode in
                return .Cancel
            })
            XCTAssertEqual(files.count, 0)
            dir.close()
            
        } catch let error as NSError {
            XCTFail(error.description)
        }
    }

}
