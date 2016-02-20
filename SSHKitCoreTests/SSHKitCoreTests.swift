//
//  SSHKitCoreTests.swift
//  SSHKitCoreTests
//
//  Created by vicalloy on 1/25/16.
//
//

import XCTest

class SSHKitCoreTests: XCTestCase, SSHKitSessionDelegate {
    // async test http://nshipster.com/xctestcase/
    var expectation: XCTestExpectation?// = expectationWithDescription("Common expectation")
    var authMethod: String?
    let username = "sshtest"
    let password = "v#.%-dzd"
    var publicKeyBase64: String?
    let task = NSTask()
    let userDefaults = NSUserDefaults.standardUserDefaults()
    
    override func setUp() {
        super.setUp()
        let publicKeyPath = NSBundle(forClass: self.dynamicType).pathForResource("ssh_host_rsa_key", ofType: "");
        do {
            publicKeyBase64 = try String(contentsOfFile: publicKeyPath!, encoding: NSUTF8StringEncoding)
        } catch {
            XCTFail("read base64 fail")
        }
        // startSSHD()
        // userDefaults.setValue("", forKey: "username")
        // userDefaults.setValue("", forKey: "password")
    }
    
    func startSSHD() {
        let hostKeyPath = NSBundle(forClass: self.dynamicType).pathForResource("ssh_host_rsa_key", ofType: "");
        let sshConfigPath = NSBundle(forClass: self.dynamicType).pathForResource("sshd_config", ofType: "");
        task.launchPath = "/usr/sbin/sshd"
        task.arguments = ["-h", hostKeyPath!, "-f", sshConfigPath!, "-p", "4000"]
        task.launch()
    }
    
    override func tearDown() {
        // Put teardown code here. This method is called after the invocation of each test method in the class.
        super.tearDown()
        // task.terminate()
    }
    
    func testConnectSessionByPublicKeyBase64() {
        expectation = expectationWithDescription("Connect Session By PublicKey Base64")
        authMethod = "publickey"
        let session = SSHKitSession(delegate: self)
        //session.connectToHost("127.0.0.1", onPort: 22, withUser: username)  // -f
        session.connectToHost("127.0.0.1", onPort: 22, withUser: username, timeout: 1)
        // NOTE: if debug(add break point), should extend this time
        waitForExpectationsWithTimeout(10) { error in
            if let error = error {
                print("Error: \(error.localizedDescription)")
            }
        }
        XCTAssert(session.connected)
    }
    
    func testConnectSessionByPassword() {
        authMethod = "password"
        expectation = expectationWithDescription("Connect Session By Password")
        let session = SSHKitSession(delegate: self)
        //session.connectToHost("127.0.0.1", onPort: 22, withUser: username)  // -f
        session.connectToHost("127.0.0.1", onPort: 22, withUser: username, timeout: 1)
        // authenticateByPasswordHandler
        waitForExpectationsWithTimeout(5) { error in
            if let error = error {
                print("Error: \(error.localizedDescription)")
            }
        }
        XCTAssert(session.connected)
    }
    
    func testConnectSessionByKeyboardInteractive() {
        authMethod = "keyboard-interactive"
        expectation = expectationWithDescription("Connect Session By Keyboard Interactive")
        let session = SSHKitSession(delegate: self)
        //session.connectToHost("127.0.0.1", onPort: 22, withUser: username)  // -f
        session.connectToHost("127.0.0.1", onPort: 22, withUser: username, timeout: 1)
        // authenticateByPasswordHandler
        waitForExpectationsWithTimeout(5) { error in
            if let error = error {
                print("Error: \(error.localizedDescription)")
            }
        }
        XCTAssert(session.connected)
    }
    
    //MARK: SSHKitSessionDelegate
    
    func session(session: SSHKitSession!, didConnectToHost host: String!, port: UInt16) {
    }
    
    func session(session: SSHKitSession!, didDisconnectWithError error: NSError!) {
        if (error != nil) {
            XCTFail("didDisconnectWithError")
            expectation!.fulfill()
        }
    }
    
    func session(session: SSHKitSession!, shouldConnectWithHostKey hostKey: SSHKitHostKeyParser!) -> Bool {
        return true
    }
    
    func session(session: SSHKitSession!, didAuthenticateUser username: String!) {
        expectation!.fulfill()
    }
    
    func session(session: SSHKitSession!, authenticateWithAllowedMethods methods: [AnyObject]!, partialSuccess: Bool) -> NSError! {
        if partialSuccess {
            // self.logInfo("Partial success. Authentication that can continue: %@", methods.componentsJoinedByString(", "))
        } else {
            // self.logInfo("Authentication that can continue: %@", methods.componentsJoinedByString(", "))
        }
        if !(methods as! [String]).contains(authMethod!) {
            XCTFail("No match authentication method found")
            expectation!.fulfill()
            return nil
        }
        
        switch authMethod! {
        case "password":
            session.authenticateByPasswordHandler({
                () in
                return self.password
            })
            break
        case "publickey":
            session.authenticateByPrivateKeyBase64(publicKeyBase64)
            break
        case "keyboard-interactive":
            session.authenticateByInteractiveHandler({
                (index:Int, name:String!, instruction:String!, prompts:[AnyObject]!) -> [AnyObject]! in
                return [self.password];
                })
            break
        case "hostbased":
            break
        case "gssapi-with-mic":
            break
        default:
            break
        }
        return nil
    }

}
