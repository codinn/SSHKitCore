//
//  SSHKitCoreTests.swift
//  SSHKitCoreTests
//
//  Created by vicalloy on 1/25/16.
//
//

import XCTest


class SSHTestsBase: XCTestCase, SSHKitSessionDelegate, SSHKitShellChannelDelegate {
    // async test http://nshipster.com/xctestcase/
    var expectation: XCTestExpectation?
    var authMethod: String?
    
    let username = "sshtest"
    let password = "v#.%-dzd"
    let identity = "ssh_rsa_key"
    
    let echoTask = NSTask()
    let echoPort : UInt16 = 6007
    
    override func setUp() {
        super.setUp()
    }
    
    override func tearDown() {
        // Put teardown code here. This method is called after the invocation of each test method in the class.
        super.tearDown()
    }
    
    // MARK: - Echo Server
    
    func startEchoServer() {
        let echoServer = NSBundle(forClass: self.dynamicType).pathForResource("echo_server.py", ofType: "");
        echoTask.launchPath = echoServer
        echoTask.arguments = ["-p", "\(echoPort)"]
        
        let pipe = NSPipe()
        echoTask.standardOutput = pipe
        echoTask.standardError = pipe
        echoTask.standardInput = NSFileHandle.fileHandleWithNullDevice()
        pipe.fileHandleForReading.readabilityHandler = { (handler: NSFileHandle?) in
            if let data = handler?.availableData {
                if let output = String(data: data, encoding: NSUTF8StringEncoding) {
                    print(output)
                }
            }
            
            self.expectation?.fulfill()
            // stop catch output
            pipe.fileHandleForReading.readabilityHandler = nil;
        }
        
        echoTask.terminationHandler = { (task: NSTask) in
            // set readabilityHandler block to nil; otherwise, you'll encounter high CPU usage
            pipe.fileHandleForReading.readabilityHandler = nil;
        }
        
        echoTask.launch()
    }
    
    func stopEchoServer() {
        echoTask.terminate()
    }
    
    func waitEchoServerStart() {
        expectation = expectationWithDescription("Wait echo server start")
        waitForExpectationsWithTimeout(5) { error in
            if let error = error {
                XCTFail(error.localizedDescription)
                self.stopEchoServer()
            }
        }
    }
    
    // MARK: - Connect Utils
    
    func connectSessionByPublicKeyBase64() -> SSHKitSession {
        expectation = expectationWithDescription("Connect Session By PublicKey Base64")
        authMethod = "publickey"
        let session = SSHKitSession(host: "127.0.0.1", port: 22, user: username, delegate: self)
        //session.connectToHost("127.0.0.1", onPort: 22, withUser: username)  // -f
        session.connectWithTimeout(1)
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
        let session = SSHKitSession(host: "127.0.0.1", port: 22, user: username, delegate: self)
        //session.connectToHost("127.0.0.1", onPort: 22, withUser: username)  // -f
        session.connectWithTimeout(1)
        waitForExpectationsWithTimeout(5) { error in
            if let error = error {
                print("Error: \(error.localizedDescription)")
            }
        }
        XCTAssert(session.connected)
        return session
        // authenticateWithAskPassword
    }
    
    func connectSessionByKeyboardInteractive() -> SSHKitSession {
        expectation = expectationWithDescription("Connect Session By Keyboard Interactive")
        authMethod = "keyboard-interactive"
        let session = SSHKitSession(host: "127.0.0.1", port: 22, user: username, delegate: self)
        //session.connectToHost("127.0.0.1", onPort: 22, withUser: username)  // -f
        session.connectWithTimeout(1)
        waitForExpectationsWithTimeout(5) { error in
            if let error = error {
                print("Error: \(error.localizedDescription)")
            }
        }
        XCTAssert(session.connected)
        return session
        // authenticateWithAskPassword
    }
    
    // MARK: - Open Channel
    
    func openDirectChannel(session: SSHKitSession) -> SSHKitChannel {
        expectation = expectationWithDescription("Open Direct Channel")
        let channel = session.openDirectChannelWithTargetHost("127.0.0.1", port: UInt(echoPort), delegate: self)
        waitForExpectationsWithTimeout(5) { error in
            if let error = error {
                print("Error: \(error.localizedDescription)")
            }
        }
        XCTAssert(channel.isOpen)
        return channel
    }
    
    
    func openShellChannel(session: SSHKitSession) -> SSHKitShellChannel {
        expectation = expectationWithDescription("Open Shell Channel")
        let channel = session.openShellChannelWithTerminalType("xterm", columns: 20, rows: 50, delegate: self)
        waitForExpectationsWithTimeout(5) { error in
            if let error = error {
                print("Error: \(error.localizedDescription)")
            }
        }
        XCTAssert(channel.isOpen)
        return channel
    }
    
    func openSFTPChannel(session: SSHKitSession) -> SSHKitSFTPChannel {
        expectation = expectationWithDescription("Open SFTP Channel")
        let channel = session.openSFTPChannel(self)
        waitForExpectationsWithTimeout(5) { error in
            if let error = error {
                print("Error: \(error.localizedDescription)")
            }
        }
        XCTAssert(channel.isOpen)
        return channel
    }
    
    func openForwardChannel(session: SSHKitSession) -> SSHKitChannel {
        expectation = expectationWithDescription("Open Forward Channel")
        let channel = session.openForwardChannel()
        waitForExpectationsWithTimeout(5) { error in
            if let error = error {
                print("Error: \(error.localizedDescription)")
            }
        }
        XCTAssert(channel.isOpen)
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
    
    func session(session: SSHKitSession!, shouldConnectWithHostKey hostKey: SSHKitHostKey!) -> Bool {
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
            session.authenticateWithAskPassword({
                () in
                return self.password
            })
            break
        case "publickey":
            let publicKeyPath = NSBundle(forClass: self.dynamicType).pathForResource(identity, ofType: "");
            
            do {
                let keyBase64 = try String(contentsOfFile: publicKeyPath!, encoding: NSUTF8StringEncoding)
                let keyPair = try SSHKitKeyPair(fromBase64: keyBase64, withAskPass: nil)
                session.authenticateWithKeyPair(keyPair)
            } catch let error as NSError {
                XCTFail(error.description)
            }
            
        case "keyboard-interactive":
            session.authenticateWithAskInteractiveInfo({
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
    }
    
    func channelDidOpen(channel: SSHKitChannel) {
        expectation!.fulfill()
    }
    
    //MARK: SSHKitShellChannelDelegate
    func channel(channel: SSHKitShellChannel, didChangePtySizeToColumns columns: Int, rows: Int, withError error: NSError) {
        // print("didChangePtySizeToColumns")
    }

}
