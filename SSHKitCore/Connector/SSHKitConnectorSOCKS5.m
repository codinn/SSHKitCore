//
//  SSHKitConnectorSOCKS5.m
//  sshproxy
//
//  Created by Yang Yubo on 11/21/14.
//  Copyright (c) 2014 Codinn. All rights reserved.
//

#import <Foundation/Foundation.h>
#import <arpa/inet.h>
#import "SSHKitConnectorProxy.h"
#import "SSHKitConnector+Protected.h"
#import "CoSocket.h"
#import "CoSOCKSMessage.h"

#define CSConnectSOCKS5Domain @"CSConnect.SOCKS5"

static NSError * socks5_do_auth_userpass(CoSocket *coSocket, NSString *username, NSString *password)
{
    //    +----+------+----------+------+----------+
    //    |VER | ULEN |  UNAME   | PLEN |  PASSWD  |
    //    +----+------+----------+------+----------+
    //    | 1  |  1   | 1 to 255 |  1   | 1 to 255 |
    //    +----+------+----------+------+----------+
    
    NSUInteger usernameLength   = [username lengthOfBytesUsingEncoding:NSUTF8StringEncoding];
    NSUInteger passwordLength   = [password lengthOfBytesUsingEncoding:NSUTF8StringEncoding];
    
    if (usernameLength>255) {
        return [NSError errorWithDomain:CSConnectSOCKS5Domain
                            code:255
                        userInfo:@{ NSLocalizedDescriptionKey : @"SOCKS5: authentication username exceeds 255 bytes" }];
    }
    
    if (passwordLength>255) {
        return [NSError errorWithDomain:CSConnectSOCKS5Domain
                            code:255
                        userInfo:@{ NSLocalizedDescriptionKey : @"SOCKS5: authentication password exceeds 255 bytes" }];
    }
    
    unsigned char buffer[1+1+255+1+255] = {0};
    NSUInteger offset = 0;
    
    buffer[offset] = 0x01;              /* subnegotiation ver.: 1 */
    offset++;
    
    buffer[offset] = usernameLength;    /* ULEN and UNAME */
    offset++;
    memcpy(buffer+offset, username.UTF8String, usernameLength);
    offset += usernameLength;
    
    buffer[offset] = passwordLength;    /* PLEN and PASSWD */
    offset++;
    memcpy(buffer+offset, password.UTF8String, passwordLength);
    offset += passwordLength;
    
    /* send it and get answer */
    NSData *data = [NSData dataWithBytesNoCopy:buffer length:offset freeWhenDone:NO];
    
    NSError *error = nil;
    if (![coSocket writeData:data error:&error]) {
        return error;
    }
    
    NSData *response = [coSocket readDataToLength:2 error:&error];   /* recv response */
    
    if (!response.length) {                 /* send request */
        return error;
    }
    
    NSInteger responseCode = ((const char *)response.bytes)[1];
    if (responseCode!=0) {
        return [NSError errorWithDomain:CSConnectSOCKS5Domain
                                   code:255
                               userInfo:@{ NSLocalizedDescriptionKey : @"SOCKS5: authentication failed" }];
    }
    
    return nil;     /* success */
}

static NSError * socks5_do_connect_target(CoSocket *coSocket, NSString *targetHost, uint16_t targetPort)
{
    NSUInteger  hostLength = [targetHost lengthOfBytesUsingEncoding:NSUTF8StringEncoding];
    
    if (hostLength > 255) {
        return [NSError errorWithDomain:CSConnectSOCKS5Domain
                                   code:255
                               userInfo:@{ NSLocalizedDescriptionKey : @"SOCKS5: authentication username exceeds 255 bytes" }];
    }
    
    unsigned char buffer[1+1+1+1+256+2] = {0};
    NSUInteger offset = 0;
    
    //      +-----+-----+-----+------+------+------+
    // NAME | VER | CMD | RSV | ATYP | ADDR | PORT |
    //      +-----+-----+-----+------+------+------+
    // SIZE |  1  |  1  |  1  |  1   | var  |  2   |
    //      +-----+-----+-----+------+------+------+
    //
    // Note: Size is in bytes
    //
    // Version      = 5 (for SOCKS5)
    // Command      = 1 (for Connect)
    // Reserved     = 0
    // Address Type = 3 (1=IPv4, 3=DomainName 4=IPv6)
    // Address      = P:D (P=LengthOfDomain D=DomainWithoutNullTermination)
    // Port         = 0
    
    // VER
    buffer[offset] = CoSOCKSVersion5;
    offset++;
    
    /* CMD
     o  CONNECT X'01'
     o  BIND X'02'
     o  UDP ASSOCIATE X'03'
     */
    buffer[offset] = CoSOCKSCommandConnect;
    offset++;
    
    // RSV, must be 0
    buffer[offset] = 0x00;
    offset++;
    
    /* ATYP
     o  IP V4 address: X'01'
     o  DOMAINNAME: X'03'
     o  IP V6 address: X'04'
     */
    buffer[offset] = CoSOCKS5AddressTypeDomainName;
    offset++;
    
    /* ADDR
     o  X'01' - the address is a version-4 IP address, with a length of 4 octets
     o  X'03' - the address field contains a fully-qualified domain name.  The first
     octet of the address field contains the number of octets of name that
     follow, there is no terminating NUL octet.
     o  X'04' - the address is a version-6 IP address, with a length of 16 octets.
     */
    buffer[offset] = hostLength;
    offset++;
    
    memcpy(buffer+offset, targetHost.UTF8String, hostLength);
    offset+=hostLength;
    
    uint16_t port = htons(targetPort);
    memcpy(buffer+offset, &port, 2);
    offset+=2;
    
    /* send it and get answer */
    NSData *data = [NSData dataWithBytesNoCopy:buffer length:offset freeWhenDone:NO];
    
    NSError *error = nil;
    if (![coSocket writeData:data error:&error]) {
        return error;
    }
    
    //      +-----+-----+-----+------+------+------+
    // NAME | VER | REP | RSV | ATYP | ADDR | PORT |
    //      +-----+-----+-----+------+------+------+
    // SIZE |  1  |  1  |  1  |  1   | var  |  2   |
    //      +-----+-----+-----+------+------+------+
    //
    // Note: Size is in bytes
    //
    // Version      = 5 (for SOCKS5)
    // Reply        = 0 (0=Succeeded, X=ErrorCode)
    // Reserved     = 0
    // Address Type = 3 (1=IPv4, 3=DomainName 4=IPv6)
    // Address      = P:D (P=LengthOfDomain D=DomainWithoutNullTermination)
    // Port         = 0
    //
    // It is expected that the SOCKS server will return the same address given in the connect request.
    // But according to XEP-65 this is only marked as a SHOULD and not a MUST.
    // So just in case, we'll read up to the address length now, and then read in the address+port next.
    
    NSData *response = [coSocket readDataToLength:4 error:&error];   /* recv response */
    
    if (!response.length) {                 /* send request */
        return error;
    }
    
    NSInteger responseCode = ((const char *)response.bytes)[1];
    
    switch (responseCode) {
        case CoSOCKS5ResponseSucceeded:
            break;
            
        case CoSOCKS5ResponseGeneralFailure:
            return [NSError errorWithDomain:CSConnectSOCKS5Domain
                                       code:255
                                   userInfo:@{ NSLocalizedDescriptionKey : @"SOCKS5: general SOCKS server failure" }];
        case CoSOCKS5ResponseNotAllowed:
            return [NSError errorWithDomain:CSConnectSOCKS5Domain
                                       code:255
                                   userInfo:@{ NSLocalizedDescriptionKey : @"SOCKS5: connection not allowed by ruleset" }];
        case CoSOCKS5ResponseNetworkUnreachable:
            return [NSError errorWithDomain:CSConnectSOCKS5Domain
                                       code:255
                                   userInfo:@{ NSLocalizedDescriptionKey : @"SOCKS5: network unreachable" }];
        case CoSOCKS5ResponseHostUnreachable:
            return [NSError errorWithDomain:CSConnectSOCKS5Domain
                                       code:255
                                   userInfo:@{ NSLocalizedDescriptionKey : @"SOCKS5: host unreachable" }];
        case CoSOCKS5ResponseRefused:
            return [NSError errorWithDomain:CSConnectSOCKS5Domain
                                       code:255
                                   userInfo:@{ NSLocalizedDescriptionKey : @"SOCKS5: connection refused" }];
        case CoSOCKS5ResponseTTLExpired:
            return [NSError errorWithDomain:CSConnectSOCKS5Domain
                                       code:255
                                   userInfo:@{ NSLocalizedDescriptionKey : @"SOCKS5: TTL expired" }];
        case CoSOCKS5ResponseCommandNotSupported:
            return [NSError errorWithDomain:CSConnectSOCKS5Domain
                                       code:255
                                   userInfo:@{ NSLocalizedDescriptionKey : @"SOCKS5: command not supported" }];
        case CoSOCKS5ResponseAddressNotSupported:
            return [NSError errorWithDomain:CSConnectSOCKS5Domain
                                       code:255
                                   userInfo:@{ NSLocalizedDescriptionKey : @"SOCKS5: address not supported" }];
        case CoSOCKS5ResponseInvalidAddress:
            return [NSError errorWithDomain:CSConnectSOCKS5Domain
                                       code:255
                                   userInfo:@{ NSLocalizedDescriptionKey : @"SOCKS5: invalid address" }];
            
        default:
            return [NSError errorWithDomain:CSConnectSOCKS5Domain
                                       code:255
                                   userInfo:@{ NSLocalizedDescriptionKey : @"SOCKS5: unknown error" }];
    }
    
    NSInteger addressType = ((const char *)response.bytes)[3];
    NSData *addressResonse = nil;
    switch (addressType) {
        case CoSOCKS5AddressTypeIPv4:     /* IP v4 ADDR*/
            addressResonse = [coSocket readDataToLength:4+2 error:&error];   /* recv IPv4 addr and port */
            break;
        case CoSOCKS5AddressTypeDomainName:     /* DOMAINNAME */
            addressResonse = [coSocket readDataToLength:1 error:&error];     /* recv name and port */
            if (!addressResonse.length) {
                return error;
            }
            
            addressResonse = [coSocket readDataToLength:((const char *)addressResonse.bytes)[0]+2 error:&error];
            break;
        case CoSOCKS5AddressTypeIPv6:     /* IP v6 ADDR */
            addressResonse = [coSocket readDataToLength:16+2 error:&error];  /* recv IPv6 addr and port */
            break;
        default:
            return [NSError errorWithDomain:CSConnectSOCKS5Domain
                                       code:255
                                   userInfo:@{ NSLocalizedDescriptionKey : @"SOCKS5: recevied unknown address type" }];
            break;
    }
    
    if (!addressResonse.length) {
        return error;
    }
    
    /* Conguraturation, connected via SOCKS5 server! */
    return nil;
}

@implementation SSHKitConnectorSOCKS5

/* begin SOCKS protocol 5 relaying
 */

- (BOOL)connectToTarget:(NSString *)host onPort:(uint16_t)port error:(NSError **)errPtr
{
    self.targetHost = host;
    self.targetPort = port;
    
    _coSocket = [[CoSocket alloc] init];
    
    if (![_coSocket connectToHost:self.proxyHost onPort:self.proxyPort withTimeout:self.timeout error:errPtr])
    {
        [self disconnect];
        return NO;
    }
    
    /**
     * Sends the SOCKS5 open/handshake/authentication data, and starts reading the response.
     * We attempt to gain anonymous access (no authentication).
     **/
    
    //      +-----+-----------+---------+
    // NAME | VER | NMETHODS  | METHODS |
    //      +-----+-----------+---------+
    // SIZE |  1  |    1      | 1 - 255 |
    //      +-----+-----------+---------+
    //
    // Note: Size is in bytes
    //
    // Version    = 5 (for SOCKS5)
    // NumMethods = 1
    // Methods    = 0 (No authentication, anonymous access)
    
    unsigned char buffer[1+1+255] = {0};
    NSUInteger offset = 0;
    
    // VER : 5
    buffer[offset] = CoSOCKSVersion5;
    offset++;
    
    if (self.proxyUsername.length && self.proxyPassword.length) {
        // no auth and user/password auth
        buffer[offset] = 0x02;
        offset++;
        
        // add no auth
        buffer[offset] = CoSOCKS5AuthMethodNoAuth;
        offset++;
        
        // add user/password auth
        buffer[offset] = CoSOCKS5AuthMethodUserPass;
        offset++;
    } else {
        // No auth
        buffer[offset] = 0x01;
        offset++;
        
        // add no auth
        buffer[offset] = CoSOCKS5AuthMethodNoAuth;
        offset++;
    }
    
    /* Send SOCKS5 open request
     */
    
    NSData *data = [NSData dataWithBytesNoCopy:buffer length:offset freeWhenDone:NO];
    
    if (![_coSocket writeData:data error:errPtr]) {                   /* send request */
        [self disconnect];
        return NO;
    }
    
    // -------------------------------------------------------------------------------------
    //      +-----+--------+
    // NAME | VER | METHOD |
    //      +-----+--------+
    // SIZE |  1  |   1    |
    //      +-----+--------+
    //
    // Note: Size is in bytes
    //
    // Version = 5 (for SOCKS5)
    // Method  = 0 (No authentication, anonymous access)
    
    
    NSData *response = [_coSocket readDataToLength:2 error:errPtr];   /* recv response */
    
    if (!response.length) {                 /* send request */
        [self disconnect];
        return NO;
    }
    
    NSInteger responseVersion = ((const char *)response.bytes)[0];
    if (responseVersion!=CoSOCKSVersion5) {
        if (errPtr) *errPtr = [NSError errorWithDomain:CSConnectSOCKS5Domain
                                            code:255
                                              userInfo:@{ NSLocalizedDescriptionKey : @"SOCKS5: peer is not a SOCKS5 proxy server" }];
        [self disconnect];
        return NO;
    }
    
    NSInteger responseAuthMethod = ((const char *)response.bytes)[1];
    
    switch ( responseAuthMethod ) {
        case CoSOCKS5AuthMethodReject:
            if (errPtr) *errPtr = [NSError errorWithDomain:CSConnectSOCKS5Domain
                                                code:255
                                            userInfo:@{ NSLocalizedDescriptionKey : @"SOCKS5: no acceptable authentication method" }];
            [self disconnect];
            return NO;     /* fail */
            
        case CoSOCKS5AuthMethodNoAuth:
            /* nothing to do */
            break;
            
        case CoSOCKS5AuthMethodUserPass:
        {
            NSError *error = socks5_do_auth_userpass(_coSocket, self.proxyUsername, self.proxyPassword);
            if (error) {
                if (errPtr) *errPtr = error;
                [self disconnect];
                return NO;     /* fail */
            }
        }
            break;
            
        default:
            if (errPtr) *errPtr = [NSError errorWithDomain:CSConnectSOCKS5Domain
                                                code:255
                                            userInfo:@{ NSLocalizedDescriptionKey : @"Unsupported authentication method" }];
            [self disconnect];
            return NO;     /* fail */
    }
    
    NSError *error = socks5_do_connect_target(_coSocket, self.targetHost, self.targetPort);
    
    if (error) {
        if (errPtr) *errPtr = error;
        [self disconnect];
        return NO;
    }
    
    return YES;
}

@end
