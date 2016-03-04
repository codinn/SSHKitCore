//
//  SSHKitCoreTests.swift
//  SSHKitCoreTests
//
//  Created by vicalloy on 1/25/16.
//
//

import XCTest

class SSHKitCoreTestsBase: XCTestCase, SSHKitSessionDelegate, SSHKitChannelDelegate {
    // async test http://nshipster.com/xctestcase/
    var expectation: XCTestExpectation?// = expectationWithDescription("Common expectation")
    var authMethod: String?
    let username = "sshtest"
    let password = "v#.%-dzd"
    var publicKeyBase64: String?
    let echoTask = NSTask()
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
    
    func startEchoServer() {
        let echoServer = NSBundle(forClass: self.dynamicType).pathForResource("echo_server.py", ofType: "");
        echoTask.launchPath = echoServer
        echoTask.launch()
    }
    
    func stopEchoServer() {
        echoTask.terminate()
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
    
    func connectSessionByPublicKeyBase64() -> SSHKitSession {
        expectation = expectationWithDescription("Connect Session By PublicKey Base64")
        authMethod = "publickey"
        let session = SSHKitSession(delegate: self)
        //session.connectToHost("127.0.0.1", onPort: 22, withUser: username)  // -f
        session.connectToHost("127.0.0.1", onPort: 22, withUser: username, timeout: 1)
        waitForExpectationsWithTimeout(10) { error in
            if let error = error {
                print("Error: \(error.localizedDescription)")
            }
        }
        XCTAssert(session.connected)
        return session
        // NOTE: if debug(add break point), should extend this time
    }
    
    func connectSessionByPassword() -> SSHKitSession {
        expectation = expectationWithDescription("Connect Session By Password")
        authMethod = "password"
        let session = SSHKitSession(delegate: self)
        //session.connectToHost("127.0.0.1", onPort: 22, withUser: username)  // -f
        session.connectToHost("127.0.0.1", onPort: 22, withUser: username, timeout: 1)
        waitForExpectationsWithTimeout(5) { error in
            if let error = error {
                print("Error: \(error.localizedDescription)")
            }
        }
        XCTAssert(session.connected)
        return session
        // authenticateByPasswordHandler
    }
    
    func connectSessionByKeyboardInteractive() -> SSHKitSession {
        expectation = expectationWithDescription("Connect Session By Keyboard Interactive")
        authMethod = "keyboard-interactive"
        let session = SSHKitSession(delegate: self)
        //session.connectToHost("127.0.0.1", onPort: 22, withUser: username)  // -f
        session.connectToHost("127.0.0.1", onPort: 22, withUser: username, timeout: 1)
        waitForExpectationsWithTimeout(5) { error in
            if let error = error {
                print("Error: \(error.localizedDescription)")
            }
        }
        XCTAssert(session.connected)
        return session
        // authenticateByPasswordHandler
    }
    
    func openDirectChannel(session: SSHKitSession) -> SSHKitChannel {
        expectation = expectationWithDescription("Open Direct Channel")
        let channel = SSHKitChannel.directChannelFromSession(session, withHost: "127.0.0.1", port: 2200, delegate: self)
        waitForExpectationsWithTimeout(5) { error in
            if let error = error {
                print("Error: \(error.localizedDescription)")
            }
        }
        XCTAssert(channel.opened)
        return channel
    }
    
    
    func openShellChannel(session: SSHKitSession) -> SSHKitChannel {
        expectation = expectationWithDescription("Open Shell Channel")
        let channel = SSHKitChannel.shellChannelFromSession(session, withTerminalType: "xterm", columns: 10, rows: 10, delegate: self)
        waitForExpectationsWithTimeout(5) { error in
            if let error = error {
                print("Error: \(error.localizedDescription)")
            }
        }
        XCTAssert(channel.opened)
        return channel
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
    
    // MARK: SSHKitChannelDelegate
    func channel(channel: SSHKitChannel, didReadStdoutData data: NSData) {
    }
    
    func channel(channel: SSHKitChannel, didReadStderrData data: NSData) {
    }
    
    func channelDidWriteData(channel: SSHKitChannel) {
    }
    
    func channelDidClose(channel: SSHKitChannel, withError error: NSError) {
        // expectation!.fulfill()
    }
    
    func channelDidOpen(channel: SSHKitChannel) {
        expectation!.fulfill()
    }
    
    func channel(channel: SSHKitChannel, didChangePtySizeToColumns columns: Int, rows: Int, withError error: NSError) {
    }

}
