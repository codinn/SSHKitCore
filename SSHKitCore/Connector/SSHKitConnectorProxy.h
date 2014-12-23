//
//  SSHKitConnectorProxy.h
//  sshproxy
//
//  Created by Yang Yubo on 11/21/14.
//  Copyright (c) 2014 Codinn. All rights reserved.
//
#import "SSHKitConnector.h"

@interface SSHKitConnectorProxy : SSHKitConnector

- (instancetype)initWithProxy:(NSString *)host onPort:(uint16_t)port timeout:(NSTimeInterval)timeout;

- (instancetype)initWithProxy:(NSString *)host onPort:(uint16_t)port username:(NSString *)username password:(NSString *)password timeout:(NSTimeInterval)timeout;

// proxy settings
@property (readonly) NSString *proxyHost;
@property (readonly) uint16_t proxyPort;

@property (readonly) NSString *proxyUsername;
@property (readonly) NSString *proxyPassword;

@property (readonly) NSTimeInterval timeout;

@property (readonly) NSString *targetHost;
@property (readonly) uint16_t targetPort;

@end


@interface SSHKitConnectorSOCKS4 : SSHKitConnectorProxy

@end


@interface SSHKitConnectorSOCKS4A : SSHKitConnectorSOCKS4

@end

@interface SSHKitConnectorSOCKS5 : SSHKitConnectorProxy

@end

@interface SSHKitConnectorHTTPS : SSHKitConnectorProxy

@end
