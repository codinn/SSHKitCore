//
//  SSHKitConnectorSOCKS4.m
//  sshproxy
//
//  Created by Yang Yubo on 11/21/14.
//  Copyright (c) 2014 Codinn. All rights reserved.
//

#import <Foundation/Foundation.h>
#import <arpa/inet.h>
#import "SSHKitConnectorProxy.h"
#import "CoSocket.h"
#import "CoSOCKSMessage.h"
#import "SSHKitConnector+Protected.h"

#define CSConnectSOCKS4Domain @"CSConnect.SOCKS4"

@interface SSHKitConnectorSOCKS4() {
@protected
    BOOL _remoteResolver;
}
@end

@implementation SSHKitConnectorSOCKS4

- (instancetype)initWithProxy:(NSString *)host onPort:(uint16_t)port username:(NSString *)username password:(NSString *)password timeout:(NSTimeInterval)timeout
{
    
    if((self = [super initWithProxy:host onPort:port username:username password:password timeout:timeout])) {
        _remoteResolver = NO;
    }
    
    return self;
}

/* begin SOCKS protocol 4 relaying
 And no authentication is supported.
 
 There's SOCKS protocol version 4 and 4a. Protocol version
 4a has capability to resolve hostname by SOCKS server, so
 we don't need resolving IP address of destination host on
 local machine.
 
 
 SOCKS4 protocol and authentication of SOCKS5 protocol
 requires user name on connect request.
 User name is determined by following method.
 
 1. If server spec has user@hostname:port format then
 user part is used for this SOCKS server.
 
 2. Get user name from environment variable LOGNAME, USER
 (in this order).
 
 */
- (BOOL)connectToTarget:(NSString *)host onPort:(uint16_t)port error:(NSError **)errPtr
{
    self.targetHost = host;
    self.targetPort = port;
    
    /* make connect request packet
     protocol v4:
     VN:1, CD:1, PORT:2, ADDR:4, USER:n, NULL:1
     protocol v4a:
     VN:1, CD:1, PORT:2, DUMMY:4, USER:n, NULL:1, HOSTNAME:n, NULL:1
     */
    if (!self.proxyUsername.length) {
        self.proxyUsername = NSUserName();
    }
    
    NSUInteger usernameLength   = [self.proxyUsername lengthOfBytesUsingEncoding:NSUTF8StringEncoding];
    NSUInteger targetHostLength = [self.targetHost lengthOfBytesUsingEncoding:NSUTF8StringEncoding];
    NSUInteger bufferLength     = 1+1+2+4 + usernameLength + 1 + targetHostLength + 1;
    
    unsigned char buffer[bufferLength];
    memset(buffer, 0, bufferLength);
    
    NSUInteger offset = 0;
    
    // VN:1
    buffer[offset] = CoSOCKSVersion4;
    offset++;
    
    /* CD
     o  CONNECT X'01'
     o  BIND X'02'
     */
    buffer[offset] = CoSOCKSCommandConnect;
    offset++;
    
    /* PORT: 2
     */
    uint16_t target_port = ntohs(self.targetPort);
    memcpy(buffer+offset, &target_port, 2);
    offset+=2;
    
    /* IP ADDRESS: 4
     */
    if (_remoteResolver) {
        offset+=3;
        
        /* fake, protocol 4a */
        buffer[offset] = 0x01;
        offset+=1;
    } else {
        NSData *address = CSConnectLocalResolveHost(self.targetHost, self.targetPort, errPtr);
        
        if (!address) {
            return NO;
        }
        
        if (![CoSocket isIPv4Address:address]) {
            *errPtr = [NSError errorWithDomain:CSConnectSOCKS4Domain
                                       code:255
                                   userInfo:@{ NSLocalizedDescriptionKey : @"IPv6 is not supported by your SOCKS4 proxy server" }];
            return NO;
        }
        
        const struct sockaddr_in *sockaddr4 = address.bytes;
        
        memcpy(buffer+offset, &sockaddr4->sin_addr, 4);
        offset+=4;
    }
    
    /* USER : n
     */
    strcpy((char *)buffer+offset, self.proxyUsername.UTF8String);
    offset+=usernameLength+1;
    
    if (_remoteResolver) {
        /* HOSTNAME :n
         */
        strcpy((char *)buffer+offset, self.targetHost.UTF8String);
        offset+=targetHostLength+1;
    }
    
    /* Connect to SOCKS4 proxy server
     */
    
    NSData *data = [NSData dataWithBytesNoCopy:buffer length:offset freeWhenDone:NO];
    _coSocket = [[CoSocket alloc] initWithHost:self.proxyHost onPort:self.proxyPort timeout:self.timeout];
    
    if (![_coSocket connect]) {
        if (errPtr) *errPtr = _coSocket.lastError;
        [self disconnect];
        return NO;
    }
    
    /* send command and get response
     response is: VN:1, CD:1, PORT:2, ADDR:4 */
    
    if (![_coSocket writeData:data]) {                   /* send request */
        if (errPtr) *errPtr = _coSocket.lastError;
        [self disconnect];
        return NO;
    }
    
    NSData *response = [_coSocket readDataToLength:8];   /* recv response */
    
    if (!response.length) {                 /* send request */
        if (errPtr) *errPtr = _coSocket.lastError;
        [self disconnect];
        return NO;
    }
    
    NSString *failureReason = nil;
    NSInteger responseCode = ((const char *)response.bytes)[1];
    
    switch ( responseCode ) {   /* check reply code */
        case CoSOCKS4ResponseSucceeded:
            break;
        case CoSOCKS4ResponseRejected:
            failureReason = @"SOCKS4: request rejected or failed";
            break;
        case CoSOCKS4ResponseIdentFail:
            failureReason = @"SOCKS4: cannot connect identd";
            break;
        case CoSOCKS4ResponseUserID:
            failureReason = @"SOCKS4: SOCKS4: user id not matched";
            break;
        default:
            failureReason = @"SOCKS4: unknown error";
            break;
    }
    
    if (failureReason.length) {
        if (errPtr) *errPtr = [NSError errorWithDomain:CSConnectSOCKS4Domain
                                                  code:responseCode
                                              userInfo:@{ NSLocalizedDescriptionKey : failureReason }];
        [self disconnect];
        return NO;
    }
    
    /* Conguraturation, connected via SOCKS4 server! */
    return YES;
}

@end


@implementation SSHKitConnectorSOCKS4A

- (instancetype)initWithProxy:(NSString *)host onPort:(uint16_t)port username:(NSString *)username password:(NSString *)password timeout:(NSTimeInterval)timeout
{
    
    if((self = [super initWithProxy:host onPort:port username:username password:password timeout:timeout])) {
        _remoteResolver = YES;
    }
    
    return self;
}

@end

