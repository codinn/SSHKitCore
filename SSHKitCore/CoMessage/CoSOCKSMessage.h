//
//  SOCKSMessage.h
//  SSH Proxy
//
//  Created by Yang Yubo on 11/26/14.
//  Copyright (c) 2014 Codinn. All rights reserved.
//

#import <Foundation/Foundation.h>

typedef NS_ENUM(uint8_t, CoSOCKS4Response) {
    CoSOCKS4ResponseSucceeded = 90,  /* rquest granted (succeeded) */
    CoSOCKS4ResponseRejected,        /* request rejected or failed */
    CoSOCKS4ResponseIdentFail,       /* cannot connect identd */
    CoSOCKS4ResponseUserID,          /* user id not matched */
};


/*
 +----+-----+-------+------+----------+----------+
 |VER | REP |  RSV  | ATYP | BND.ADDR | BND.PORT |
 +----+-----+-------+------+----------+----------+
 | 1  |  1  | X'00' |  1   | Variable |    2     |
 +----+-----+-------+------+----------+----------+
 
 o  VER    protocol version: X'05'
 o  REP    Reply field:
 o  X'00' succeeded
 o  X'01' general SOCKS server failure
 o  X'02' connection not allowed by ruleset
 o  X'03' Network unreachable
 o  X'04' Host unreachable
 o  X'05' Connection refused
 o  X'06' TTL expired
 o  X'07' Command not supported
 o  X'08' Address type not supported
 o  X'09' to X'FF' unassigned
 o  RSV    RESERVED
 o  ATYP   address type of following address
 o  IP V4 address: X'01'
 o  DOMAINNAME: X'03'
 o  IP V6 address: X'04'
 o  BND.ADDR       server bound address
 o  BND.PORT       server bound port in network octet order
 */

typedef NS_ENUM(uint8_t, CoSOCKS5Response) {
    /* informations for SOCKS5 */
    CoSOCKS5ResponseSucceeded               = 0x00,    /* succeeded */
    CoSOCKS5ResponseGeneralFailure          = 0x01,    /* general SOCKS server failure */
    CoSOCKS5ResponseNotAllowed              = 0x02,    /* connection not allowed by ruleset */
    CoSOCKS5ResponseNetworkUnreachable      = 0x03,    /* Network unreachable */
    CoSOCKS5ResponseHostUnreachable         = 0x04,    /* Host unreachable */
    CoSOCKS5ResponseRefused                 = 0x05,    /* connection refused */
    CoSOCKS5ResponseTTLExpired              = 0x06,    /* TTL expired */
    CoSOCKS5ResponseCommandNotSupported     = 0x07,    /* Command not supported */
    CoSOCKS5ResponseAddressNotSupported     = 0x08,    /* Address not supported */
    CoSOCKS5ResponseInvalidAddress          = 0x09,    /* Invalid address */
};

typedef NS_ENUM(uint8_t, CoSOCKS5AuthMethod) {
    /* SOCKS5 authentication methods */
    CoSOCKS5AuthMethodReject    = 0xFF,    /* No acceptable auth method */
    CoSOCKS5AuthMethodNoAuth    = 0x00,    /* without authentication */
    CoSOCKS5AuthMethodGSSAPI    = 0x01,    /* GSSAPI */
    CoSOCKS5AuthMethodUserPass  = 0x02,    /* User/Password */
    CoSOCKS5AuthMethodCHAP      = 0x03,    /* Challenge-Handshake Auth Proto. */
    CoSOCKS5AuthMethodEAP       = 0x05,    /* Extensible Authentication Proto. */
    CoSOCKS5AuthMethodMAF       = 0x08,    /* Multi-Authentication Framework */
};

typedef NS_ENUM(uint8_t, CoSOCKSVersionNumber) {
    CoSOCKSVersion4     = 0x04,
    CoSOCKSVersion5     = 0x05,
};

typedef NS_ENUM(uint8_t, CoSOCKSCommand) {
    CoSOCKSCommandConnect          = 0x01,
    CoSOCKSCommandBind             = 0x02,
    CoSOCKSCommandUDPAssociate     = 0x03
};

typedef NS_ENUM(uint8_t, CoSOCKS5AddressType) {
    CoSOCKS5AddressTypeIPv4         = 0x01,
    CoSOCKS5AddressTypeDomainName   = 0x03,
    CoSOCKS5AddressTypeIPv6         = 0x04,
};

/*
 o  X'00' NO AUTHENTICATION REQUIRED
 o  X'01' GSSAPI
 o  X'02' USERNAME/PASSWORD
 o  X'03' to X'7F' IANA ASSIGNED
 o  X'80' to X'FE' RESERVED FOR PRIVATE METHODS
 o  X'FF' NO ACCEPTABLE METHODS
 */

typedef NS_ENUM(uint8_t, CoSOCKS5AuthenticationMethod) {
    CoSOCKS5AuthenticationNone = 0x00,
    CoSOCKS5AuthenticationGSSAPI = 0x01,
    CoSOCKS5AuthenticationUsernamePassword = 0x02
};


@interface CoSOCKSMessage : NSObject

@end
