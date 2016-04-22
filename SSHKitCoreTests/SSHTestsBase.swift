//
//  SSHKitCoreTests.swift
//  SSHKitCoreTests
//
//  Created by vicalloy on 1/25/16.
//
//

import XCTest

enum AuthMethod: String {
    case Password       = "password"
    case PublicKey      = "publickey"
    case Interactive    = "keyboard-interactive"
}

class SSHTestsBase: XCTestCase, SSHKitSessionDelegate, SSHKitShellChannelDelegate {
    // async test http://nshipster.com/xctestcase/
    var expectation: XCTestExpectation?
    private var authMethods = [AuthMethod.Password, ]
    
    let sshHost  = "127.0.0.1"
    let sshPort : UInt16 = 22
    
    var username = "sshtest"
    let password = "v#.%-dzd"
    let identity = "ssh_rsa_key"
    
    let echoTask = NSTask()
    let echoPort : UInt16 = 6007
    
    var error : NSError?
    
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
    
    func launchSessionWithAuthMethod(method: AuthMethod) throws -> SSHKitSession {
        return try launchSessionWithAuthMethods([method,])
    }
    
    func launchSessionWithAuthMethods(methods: [AuthMethod]) throws -> SSHKitSession {
        expectation = expectationWithDescription("Launch session with \(methods) auth method")
        authMethods = methods
        
        let session = SSHKitSession(host: sshHost, port: sshPort, user: username, delegate: self)
        session.connectWithTimeout(1)
        
        waitForExpectationsWithTimeout(1) { error in
            if let error = error {
                XCTFail(error.localizedDescription)
            }
        }
        
        if let error = self.error {
            throw error
        }
        
        return session
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
        if error != nil {
            self.error = error
            expectation!.fulfill()
        }
    }
    
    func session(session: SSHKitSession!, shouldConnectWithHostKey hostKey: SSHKitHostKey!) -> Bool {
        return true
    }
    
    func session(session: SSHKitSession!, didAuthenticateUser username: String!) {
        expectation!.fulfill()
    }
    
    func session(session: SSHKitSession!, authenticateWithAllowedMethods methods: [String]!, partialSuccess: Bool) -> NSError! {
        if partialSuccess {
            // self.logInfo("Partial success. Authentication that can continue: %@", methods.componentsJoinedByString(", "))
        } else {
            // self.logInfo("Authentication that can continue: %@", methods.componentsJoinedByString(", "))
        }
        
        if let firstMethod = methods.first {
            if let matched = AuthMethod(rawValue: firstMethod) {
                switch matched {
                case .Password:
                    session.authenticateWithAskPassword({
                        () in
                        return self.password
                    })
                    
                case .PublicKey:
                    let publicKeyPath = NSBundle(forClass: self.dynamicType).pathForResource(identity, ofType: "");
                    
                    do {
                        let keyBase64 = try String(contentsOfFile: publicKeyPath!, encoding: NSUTF8StringEncoding)
                        let keyPair = try SSHKitKeyPair(fromBase64: keyBase64, withAskPass: nil)
                        session.authenticateWithKeyPair(keyPair)
                    } catch let error as NSError {
                        XCTFail(error.description)
                    }
                    
                case .Interactive:
                    session.authenticateWithAskInteractiveInfo({
                        (index:Int, name:String!, instruction:String!, prompts:[AnyObject]!) -> [AnyObject]! in
                        return [self.password];
                    })
                }
            } else {
                XCTFail("No match authentication method found: \(firstMethod)")
                expectation!.fulfill()
                return nil
            }
        } else {
            XCTFail("authenticateWithAllowedMethods passed in empty auth methods array: \(methods)")
            expectation!.fulfill()
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
        self.error = error;
    }
    
    func channelDidOpen(channel: SSHKitChannel) {
        expectation!.fulfill()
    }
    
    //MARK: SSHKitShellChannelDelegate
    func channel(channel: SSHKitShellChannel, didChangePtySizeToColumns columns: Int, rows: Int, withError error: NSError) {
        // print("didChangePtySizeToColumns")
    }

}
