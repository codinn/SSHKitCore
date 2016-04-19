//
//  KeyPairTests.swift
//  SSHKitCore
//
//  Created by Yang Yubo on 4/19/16.
//
//

import XCTest

class KeyPairTests: XCTestCase {

    override func setUp() {
        super.setUp()
        // Put setup code here. This method is called before the invocation of each test method in the class.
    }
    
    override func tearDown() {
        // Put teardown code here. This method is called after the invocation of each test method in the class.
        super.tearDown()
    }
    
    
    func doTestUnencryptedKeyPair(name:String) {
        let path = NSBundle(forClass: self.dynamicType).pathForResource(name, ofType: "");
        
        do {
            let parser = try SSHKitKeyPair.init(fromFilePath: path, withAskPass: nil)
            XCTAssertNotNil(parser)
        } catch let error as NSError {
            XCTFail(error.description)
        }
    }
    
    func doTestEncryptedKeyPair(name:String) {
        let path = NSBundle(forClass: self.dynamicType).pathForResource(name, ofType: "");
        let block :SSHKitAskPassBlock = {
            return "lollipop"
        }
        
        do {
            let parser = try SSHKitKeyPair.init(fromFilePath: path, withAskPass: block)
            XCTAssertNotNil(parser)
        } catch let error as NSError {
            XCTFail(error.description)
        }
    }
    
    func doTestEncryptedKeyPairWithIncorrectPassphrase(name:String) {
        let path = NSBundle(forClass: self.dynamicType).pathForResource(name, ofType: "");
        let block :SSHKitAskPassBlock = {
            return "incorrect-passphrase"
        }
        
        do {
            let parser = try SSHKitKeyPair.init(fromFilePath: path, withAskPass: block)
            XCTAssertNotNil(parser)
        } catch let error as NSError {
            XCTAssertEqual(SSHKitErrorCode.IdentityParseFailure.rawValue, error.code, error.description)
            return
        }
        
        XCTFail("Key pair initialization should fail!")
    }
    
    func doTestEncryptedKeyPairWithNilAskPassBlock(name:String) {
        let path = NSBundle(forClass: self.dynamicType).pathForResource(name, ofType: "");
        
        do {
            let parser = try SSHKitKeyPair.init(fromFilePath: path, withAskPass: nil)
            XCTAssertNotNil(parser)
        } catch let error as NSError {
            XCTAssertEqual(SSHKitErrorCode.IdentityParseFailure.rawValue, error.code, error.description)
            return
        }
        
        XCTFail("Key pair initialization should fail!")
    }
    
    func testEncryptedKeyPair() {
        doTestEncryptedKeyPair("id_rsa_password")
        doTestEncryptedKeyPair("id_ecdsa_password")
        doTestEncryptedKeyPair("id_ed25519_password")
    }
    
    func testEncryptedKeyPairWithIncorrectPassphrase() {
        doTestEncryptedKeyPairWithIncorrectPassphrase("id_rsa_password")
        doTestEncryptedKeyPairWithIncorrectPassphrase("id_ecdsa_password")
        doTestEncryptedKeyPairWithIncorrectPassphrase("id_ed25519_password")
    }
    
    func testEncryptedKeyPairWithNilAskPassBlock() {
        doTestEncryptedKeyPairWithNilAskPassBlock("id_rsa_password")
        doTestEncryptedKeyPairWithNilAskPassBlock("id_ecdsa_password")
        doTestEncryptedKeyPairWithNilAskPassBlock("id_ed25519_password")
    }
    
    func testUnencryptedKeyPair() {
        doTestUnencryptedKeyPair("id_dsa")
        doTestUnencryptedKeyPair("id_rsa")
        doTestUnencryptedKeyPair("id_rsa_4096")
        doTestUnencryptedKeyPair("id_ed25519")
        doTestUnencryptedKeyPair("id_ecdsa")
    }
    
    /*
      Libssh does not support pkcs8 naturally
     */
    
    func doTestUnencryptedPKCS8KeyPair(name:String) {
        let path = NSBundle(forClass: self.dynamicType).pathForResource(name, ofType: "");
        
        do {
            let parser = try SSHKitKeyPair.init(fromFilePath: path, withAskPass: nil)
            XCTAssertNotNil(parser)
        } catch let error as NSError {
            XCTAssertEqual(SSHKitErrorCode.IdentityParseFailure.rawValue, error.code, error.description)
            return
        }
        
        XCTFail("PKCS#8 key pair initialization should fail!")
    }
    
    func doTestEncryptedPKCS8KeyPair(name:String) {
        let path = NSBundle(forClass: self.dynamicType).pathForResource(name, ofType: "");
        let block :SSHKitAskPassBlock = {
            return "lollipop"
        }
        
        do {
            let parser = try SSHKitKeyPair.init(fromFilePath: path, withAskPass: block)
            XCTAssertNotNil(parser)
        } catch let error as NSError {
            XCTAssertEqual(SSHKitErrorCode.IdentityParseFailure.rawValue, error.code, error.description)
            return
        }
        
        XCTFail("PKCS#8 key pair initialization should fail!")
    }
    
    func testPKCS8() {
        doTestUnencryptedPKCS8KeyPair("id_dsa.pkcs8")
        doTestUnencryptedPKCS8KeyPair("id_rsa.pkcs8")
        doTestEncryptedPKCS8KeyPair("id_dsa.pkcs8.password")
        doTestEncryptedPKCS8KeyPair("id_rsa.pkcs8.password")
    }
    
    // TODO: Add tests for base64 api
}
