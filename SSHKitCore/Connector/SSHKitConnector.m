//
//  SSHKitConnector.m
//  SSHKitCore
//
//  Created by Yang Yubo on 12/23/14.
//
//

#import "SSHKitConnector.h"
#import "CoSocket.h"
#import "CoSOCKSMessage.h"
#import "SSHKitConnector+Protected.h"

@implementation SSHKitConnector

@end

@implementation SSHKitConnectorProxy

- (instancetype)initWithProxyHost:(NSString *)host port:(uint16_t)port
{
    return [self initWithProxyHost:host port:port username:nil password:nil];
}
- (instancetype)initWithProxyHost:(NSString *)host port:(uint16_t)port username:(NSString *)username password:(NSString *)password
{
    if((self = [super init])) {
        self.proxyHost = host;
        self.proxyPort = port;
        self.proxyUsername = username;
        self.proxyPassword = password;
    }
    
    return self;
}

@end
