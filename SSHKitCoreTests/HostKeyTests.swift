//
//  HostKeyTests.swift
//  SSHKitCore
//
//  Created by Yang Yubo on 4/19/16.
//
//

import XCTest

class HostKeyTests: XCTestCase {

    override func setUp() {
        super.setUp()
        // Put setup code here. This method is called before the invocation of each test method in the class.
    }
    
    override func tearDown() {
        // Put teardown code here. This method is called after the invocation of each test method in the class.
        super.tearDown()
    }
    
    // MARK: - Valid base64
    // Use command "ssh-keygen -l -E md5 -f ssh_host_dsa_key.pub" to calculate fingerprint

    func testDSABase64() {
        let type = SSHKitHostKeyTypeFromName("ssh-dss")
        do {
            let hostKey = try SSHKitHostKey.init(fromBase64: "AAAAB3NzaC1kc3MAAACBAK3KB5czAtQLGTNz/Y6cq1duk24WxsZ1iHVNYpyk8DdOOfAWhUn2VoO3MBmE5rfn4C4fP4V3k+Yz0UwPJcj94oSP0D1ENAGlwZ/WKqFHDGxNlsT7klaSEEnYxVRqbmkRzXbqA4Ey0sisQlRVH5Hg1LW0F9d7w33C7cWcR87KwFUxAAAAFQDX5DpgN1ZPIiwlVu7USLc1K0xzhQAAAIEAgdQNWe6XpS3XtHW2nTxDtyj5Q2Gb9IB+KaemY410UnCaXgGrQhmy8IBhlq8z81JuXIPXUj6NvaaCFnOgA5SGJBSII6B8bLLQvIUEMooIuV7CbYqnGfXaVjoE5WQmQFsqRXB+4vauqswZTUFrnbnN96NwZ2Yvsi0KfieKBI/UbV4AAACAFo/2etp5aLREoqJcTiv/J3XOojT7flELCdhMTNIDcU2mQPzXmlk3lP4XN9lg2JpPjse+sBEE+AiAB9NwfpBs1Dt2p8Eer5RbYt5TStThFZrUwZ9exwLR7KEFvplhVytE+prs5EZmge+7swHewqktnBWl7pa+HInlxQXXzYGSkJg=", withType: type)
            XCTAssertEqual(hostKey.fingerprint, "7f:26:dd:58:61:18:20:c1:be:e3:79:7e:2e:39:9a:1e")
        } catch let error as NSError {
            XCTFail(error.description)
        }
    }
    
    func testECDSABase64() {
        let type = SSHKitHostKeyTypeFromName("ssh-ecdsa")
        do {
            let hostKey = try SSHKitHostKey.init(fromBase64: "AAAAE2VjZHNhLXNoYTItbmlzdHAyNTYAAAAIbmlzdHAyNTYAAABBBFptaLP78qdcAmxfJ+h7oLSmcwP9Czi8JF2Q3y3GWCz480w7pGWuJNI83ModtXsrSuMVHHEYFYUVkOUKkZv00s4=", withType: type)
            XCTAssertEqual(hostKey.fingerprint, "6b:ac:92:e9:65:86:b8:03:52:52:d7:0a:b8:f8:30:1d")
        } catch let error as NSError {
            XCTFail(error.description)
        }
    }
    
    func testED25519Base64() {
        let type = SSHKitHostKeyTypeFromName("ssh-ed25519")
        do {
            let hostKey = try SSHKitHostKey.init(fromBase64: "AAAAC3NzaC1lZDI1NTE5AAAAIENqyrs+ld8H3fu7xebmZZgCBkCiRTem7SkLeGma2NTf", withType: type)
            XCTAssertEqual(hostKey.fingerprint, "7d:8f:5f:84:7e:26:fa:55:9f:cb:d5:68:d4:33:06:2c")
        } catch let error as NSError {
            XCTFail(error.description)
        }
    }
    
    func testRSABase64() {
        let type = SSHKitHostKeyTypeFromName("ssh-rsa")
        do {
            let hostKey = try SSHKitHostKey.init(fromBase64: "AAAAB3NzaC1yc2EAAAADAQABAAABAQDI/8zzp1P6FtQoJkdTwtKZ86/QAqQSiT8Og/Tl8cNfi3UudwgTRdgLAwjc3Cei64Y0btHhRdGS91QLHllCk9Ssq3YEdUBCCv8fdEzFB3KRDv22ODSsguB67LxyqLV9twKVrjlBgmTzW3akogeR61NjEbKGsI3Z0eYUDNhX7NQ4d+mwKX6ZzcRAgGaye3fb34b/GgJZZyxW5t2w2n7UXdyOceNsA+yzqjQwi5UK25NWn6sINNxEt09p4zq8vNi2bhGDzSp71zpZu+st+eGwMBOdeKmnguXn96U978m4x76pFdnOY4bjBILDQHeouwYfEmw/sV85r6JngsNsQpeVCjpN", withType: type)
            XCTAssertEqual(hostKey.fingerprint, "70:47:0c:ab:5b:64:9f:cd:a1:fe:e9:4a:50:8d:84:b2")
        } catch let error as NSError {
            XCTFail(error.description)
        }
    }
    
    // MARK: - Invalid base64
    
    func testED25519InvalidBase64() {
        let type = SSHKitHostKeyTypeFromName("ssh-ed25519")
        do {
            let _ = try SSHKitHostKey.init(fromBase64: "AAAA3NzaC1lZDI1NTE5AAAAIENqyrs+ld8H3fu7xebmZZgCBkCiRTem7SkLeGma2NTf", withType: type)
        } catch let error as NSError {
            XCTAssertEqual(SSHKitErrorCode.HostKeyMismatch.rawValue, error.code, error.description)
            return
        }
        
        XCTFail("Host key initializing should fail")
    }
    
    // MARK: - Invalid key type
    
    func testInvalidKeyType() {
        let type = SSHKitHostKeyTypeFromName("ssh-invalid")
        do {
            let _ = try SSHKitHostKey.init(fromBase64: "AAAAB3NzaC1yc2EAAAADAQABAAABAQDI/8zzp1P6FtQoJkdTwtKZ86/QAqQSiT8Og/Tl8cNfi3UudwgTRdgLAwjc3Cei64Y0btHhRdGS91QLHllCk9Ssq3YEdUBCCv8fdEzFB3KRDv22ODSsguB67LxyqLV9twKVrjlBgmTzW3akogeR61NjEbKGsI3Z0eYUDNhX7NQ4d+mwKX6ZzcRAgGaye3fb34b/GgJZZyxW5t2w2n7UXdyOceNsA+yzqjQwi5UK25NWn6sINNxEt09p4zq8vNi2bhGDzSp71zpZu+st+eGwMBOdeKmnguXn96U978m4x76pFdnOY4bjBILDQHeouwYfEmw/sV85r6JngsNsQpeVCjpN", withType: type)
        } catch let error as NSError {
            XCTAssertEqual(SSHKitErrorCode.HostKeyMismatch.rawValue, error.code, error.description)
            return
        }
        
        XCTFail("Host key initializing should fail")
    }
}
