//
//  ConnectTests.swift
//  SSHKitCore
//
//  Created by vicalloy on 2/21/16.
//
//

import XCTest

class SessionTests: SessionTestCase {

    override func setUp() {
        super.setUp()
        // Put setup code here. This method is called before the invocation of each test method in the class.
    }
    
    override func tearDown() {
        // Put teardown code here. This method is called after the invocation of each test method in the class.
        super.tearDown()
    }
    
    // MARK: - Connect
    
    func testSessionConnectWithNonRoutableIP() {
        do {
            let session = try launchSessionWithTimeoutHost()
            XCTAssertNotNil(session)
        } catch let error as NSError {
            XCTAssertEqual(SSHKitErrorCode.Timeout.rawValue, error.code, error.description)
            return
        }
        
        XCTFail("An connect error not raised as expected")
    }
    
    func testSessionConnectWithRefusePort() {
        do {
            let session = try launchSessionWithRefusePort()
            XCTAssertNotNil(session)
        } catch let error as NSError {
            XCTAssertEqual(SSHKitErrorCode.Fatal.rawValue, error.code, error.description)
            return
        }
        
        XCTFail("An connect error not raised as expected")
    }
    
    // MARK: - Disconnect
    
    func testSessionDisconnect() {
        do {
            let session = try launchSessionWithAuthMethod(.PublicKey, user: userForSFA)
            XCTAssert(session.connected)
            XCTAssertFalse(session.disconnected)
            
            try disconnectSessionAndWait(session)
            XCTAssertFalse(session.connected)
            XCTAssert(session.disconnected)
        } catch let error as NSError {
            XCTFail(error.description)
        }
    }
    
    // MARK: - Trivial Properties
    
    func testTrivialProperties() {
        do {
            let session = try launchSessionWithAuthMethod(.PublicKey, user: userForSFA)
            XCTAssertEqual(session.host, sshHost)
            XCTAssertEqual(session.port, sshPort)
            XCTAssertEqual(session.username, userForSFA)
            XCTAssertGreaterThan(session.fd, -1)
        } catch let error as NSError {
            XCTFail(error.description)
        }
    }
    
    // MARK: - Authentication
    
    func testSessionConnectWithInvalidUser() {
        do {
            try launchSessionWithAuthMethods([.PublicKey, .Password, .Interactive], user: invalidUser)
        } catch let error as NSError {
            XCTAssertEqual(SSHKitErrorCode.RequestDenied.rawValue, error.code, error.description)
            return
        }
        
        XCTFail("An auth error not raised as expected")
    }
    
    func testSessionConnectWithInvalidPass() {
        let correctPassword = password
        password = "invalid-password"
        
        defer {
            // recover changed password for other tests
            password = correctPassword
        }
        
        do {
            try launchSessionWithAuthMethods([.PublicKey, .Password, .Interactive], user: userForSFA)
        } catch let error as NSError {
            XCTAssertEqual(SSHKitErrorCode.RequestDenied.rawValue, error.code, error.description)
            return
        }
        
        XCTFail("An auth error not raised as expected")
    }

    func testSessionSingleFactorAuth() {
        do {
            try launchSessionWithAuthMethod(.PublicKey, user: userForSFA)
            try launchSessionWithAuthMethod(.Password, user: userForSFA)
            try launchSessionWithAuthMethod(.Interactive, user: userForSFA)
        } catch let error as NSError {
            XCTFail(error.description)
        }
    }
    
    func testSessionMultiFactorAuth() {
        do {
            try launchSessionWithAuthMethods([.PublicKey, .Password, .Interactive], user: userForMFA)
        } catch let error as NSError {
            XCTFail(error.description)
        }
    }
    
    func testSessionAuthFail() {
        do {
            try launchSessionWithAuthMethods([.PublicKey, .Password, .Interactive], user: userForNoPass)
        } catch let error as NSError {
            XCTAssertEqual(SSHKitErrorCode.RequestDenied.rawValue, error.code, error.description)
            return
        }
        
        XCTFail("An auth error not raised as expected")
    }
    
    // MARK: - Host Key Algorithms
    
    func testNoHostKeyAlgorithms() {
        do {
            let _ = try self.launchSessionWithAuthMethod(.Password, user: userForSFA)
            
            if let hostKey = self.hostKey {
                // we don't test key type here, since XCTest is not run under sanbox, so the preferred
                // host key order will be affected by ~/.ssh/known_hosts as described in libssh source code
                XCTAssertNotNil(hostKey.base64)
                XCTAssertNotNil(hostKey.fingerprint)
            } else {
                XCTFail("Could not get host key")
            }
        } catch let error as NSError {
            XCTFail(error.description)
        }
    }
    
    func testDefaultHostKeyAlgorithms() {
        do {
            let _ = try self.launchSessionWithAuthMethod(.Password, user: userForSFA, options: [kVTKitHostKeyAlgorithmsKey:"ssh-ed25519,ecdsa-sha2-nistp521,ecdsa-sha2-nistp384,ecdsa-sha2-nistp256,ssh-rsa,ssh-dss,ssh-rsa1"])
            
            if let hostKey = self.hostKey {
                let keyType = SSHKitHostKeyTypeFromName("ssh-ed25519")
                XCTAssertEqual(hostKey.keyType, keyType)
                XCTAssertNotNil(hostKey.base64)
                XCTAssertNotNil(hostKey.fingerprint)
            } else {
                XCTFail("Could not get host key")
            }
        } catch let error as NSError {
            XCTFail(error.description)
        }
    }
    
    func testECDSAHostKeyAlgorithms() {
        do {
            let _ = try self.launchSessionWithAuthMethod(.Password, user: userForSFA, options: [kVTKitHostKeyAlgorithmsKey:"ecdsa-sha2-nistp521,ecdsa-sha2-nistp384,ecdsa-sha2-nistp256,ssh-rsa,ssh-dss,ssh-rsa1,ssh-ed25519"])
            
            if let hostKey = self.hostKey {
                let keyType = SSHKitHostKeyTypeFromName("ecdsa-sha2-nistp521")
                XCTAssertEqual(hostKey.keyType, keyType)
                XCTAssertNotNil(hostKey.base64)
                XCTAssertNotNil(hostKey.fingerprint)
            } else {
                XCTFail("Could not get host key")
            }
        } catch let error as NSError {
            XCTFail(error.description)
        }
    }
    
    func testRSAHostKeyAlgorithms() {
        do {
            let _ = try self.launchSessionWithAuthMethod(.Password, user: userForSFA, options: [kVTKitHostKeyAlgorithmsKey:"ssh-rsa,ecdsa-sha2-nistp521,ecdsa-sha2-nistp384,ecdsa-sha2-nistp256,ssh-dss,ssh-rsa1,ssh-ed25519"])
            
            if let hostKey = self.hostKey {
                let keyType = SSHKitHostKeyTypeFromName("ssh-rsa")
                XCTAssertEqual(hostKey.keyType, keyType)
                XCTAssertNotNil(hostKey.base64)
                XCTAssertNotNil(hostKey.fingerprint)
            } else {
                XCTFail("Could not get host key")
            }
        } catch let error as NSError {
            XCTFail(error.description)
        }
    }
    
    func testDSAHostKeyAlgorithms() {
        do {
            let _ = try self.launchSessionWithAuthMethod(.Password, user: userForSFA, options: [kVTKitHostKeyAlgorithmsKey:"ssh-dss,ssh-rsa,ecdsa-sha2-nistp521,ecdsa-sha2-nistp384,ecdsa-sha2-nistp256,ssh-rsa1,ssh-ed25519"])
            
            if let hostKey = self.hostKey {
                let keyType = SSHKitHostKeyTypeFromName("ssh-dss")
                XCTAssertEqual(hostKey.keyType, keyType)
                XCTAssertNotNil(hostKey.base64)
                XCTAssertNotNil(hostKey.fingerprint)
            } else {
                XCTFail("Could not get host key")
            }
        } catch let error as NSError {
            XCTFail(error.description)
        }
    }
    
    func testInvalidHostKeyAlgorithms() {
        do {
            let _ = try self.launchSessionWithAuthMethod(.Password, user: userForSFA, options: [kVTKitHostKeyAlgorithmsKey:"invalid-hostkey-algorithms"])
        } catch let error as NSError {
            XCTAssertEqual(SSHKitErrorCode.RequestDenied.rawValue, error.code, error.description)
            return
        }
        
        XCTFail("An settings fatal error not raised as expected")
    }
    
    // MARK: - Compress
    
    func testCompressEnabled() {
        do {
            let session = try self.launchSessionWithAuthMethod(.Password, user: userForSFA, options: [kVTKitEnableCompressionKey:true])
            
            XCTAssert(session.connected)
            XCTAssertFalse(session.disconnected)
            
            try disconnectSessionAndWait(session)
            XCTAssertFalse(session.connected)
            XCTAssert(session.disconnected)
        } catch let error as NSError {
            XCTFail(error.description)
        }
    }
    
    func testCompressDisabledExplicitly() {
        do {
            let session = try self.launchSessionWithAuthMethod(.Password, user: userForSFA, options: [kVTKitEnableCompressionKey:false])
            
            XCTAssert(session.connected)
            XCTAssertFalse(session.disconnected)
            
            try disconnectSessionAndWait(session)
            XCTAssertFalse(session.connected)
            XCTAssert(session.disconnected)
        } catch let error as NSError {
            XCTFail(error.description)
        }
    }
    
    // MARK: - Negotiation Algorithms
    
    func testDefaultNegotiationAlgorithms() {
        do {
            let _ = try self.launchSessionWithAuthMethod(.Password, user: userForSFA)
            
            XCTAssertNotNil(currentHMAC)
            XCTAssertNotNil(currentCipher)
            XCTAssertNotNil(currentKEXAlgo)
        } catch let error as NSError {
            XCTFail(error.description)
        }
    }
    
    func testModifiedNegotiationAlgorithms() {
        do {
            let options = [
                kVTKitMACAlgorithmsKey      : "hmac-sha2-512,hmac-sha2-256,hmac-sha1",
                kVTKitEncryptionCiphersKey  : "aes128-ctr,blowfish-cbc,aes256-ctr,aes192-ctr,aes256-cbc,aes192-cbc,aes128-cbc,3des-cbc",
                kVTKitKeyExchangeAlgorithmsKey: "ecdh-sha2-nistp256,curve25519-sha256@libssh.org,diffie-hellman-group14-sha1,diffie-hellman-group1-sha1"
            ]
            
            let _ = try self.launchSessionWithAuthMethod(.Password, user: userForSFA, options: options)
            
            XCTAssertEqual(currentHMAC, "hmac-sha2-512")
            XCTAssertEqual(currentCipher, "aes128-ctr")
            XCTAssertEqual(currentKEXAlgo, "ecdh-sha2-nistp256")
        } catch let error as NSError {
            XCTFail(error.description)
        }
    }
    
    func testInvalidMACAlgorithms() {
        do {
            let _ = try self.launchSessionWithAuthMethod(.Password, user: userForSFA, options: [kVTKitMACAlgorithmsKey:"invalid-hmac-algorithms"])
        } catch let error as NSError {
            XCTAssertEqual(SSHKitErrorCode.RequestDenied.rawValue, error.code, error.description)
            return
        }
        
        XCTFail("An settings fatal error not raised as expected")
    }
    
    func testInvalidCipherAlgorithms() {
        do {
            let _ = try self.launchSessionWithAuthMethod(.Password, user: userForSFA, options: [kVTKitEncryptionCiphersKey:"invalid-cipher-algorithms"])
        } catch let error as NSError {
            XCTAssertEqual(SSHKitErrorCode.RequestDenied.rawValue, error.code, error.description)
            return
        }
        
        XCTFail("An settings fatal error not raised as expected")
    }
    
    func testInvalidKEXAlgorithms() {
        do {
            let _ = try self.launchSessionWithAuthMethod(.Password, user: userForSFA, options: [kVTKitKeyExchangeAlgorithmsKey:"invalid-kex-algorithms"])
        } catch let error as NSError {
            XCTAssertEqual(SSHKitErrorCode.RequestDenied.rawValue, error.code, error.description)
            return
        }
        
        XCTFail("An settings fatal error not raised as expected")
    }
}
