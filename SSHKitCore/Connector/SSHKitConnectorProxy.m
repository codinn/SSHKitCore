//
//  SSHKitConnectorProxy.m
//  sshproxy
//
//  Created by Yang Yubo on 11/21/14.
//  Copyright (c) 2014 Codinn. All rights reserved.
//

#import <Foundation/Foundation.h>
#import "SSHKitConnectorProxy.h"
#import "SSHKitConnector+Protected.h"

@implementation SSHKitConnectorProxy

- (instancetype)initWithProxy:(NSString *)host onPort:(uint16_t)port timeout:(NSTimeInterval)timeout
{
    return [self initWithProxy:host onPort:port username:nil password:nil timeout:timeout];
}
- (instancetype)initWithProxy:(NSString *)host onPort:(uint16_t)port username:(NSString *)username password:(NSString *)password timeout:(NSTimeInterval)timeout
{
    if((self = [super init])) {
        self.proxyHost = host;
        self.proxyPort = port;
        self.proxyUsername = username;
        self.proxyPassword = password;
        self.timeout = timeout;
    }
    
    return self;
}

@end
