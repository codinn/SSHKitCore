//
//  SSHKitConnector.h
//  SSHKitCore
//
//  Created by Yang Yubo on 12/23/14.
//
//

#import <Foundation/Foundation.h>
#import "CoSocket.h"

@interface SSHKitConnector : CoSocket

@end

@interface SSHKitConnectorProxy : SSHKitConnector

- (instancetype)initWithProxyHost:(NSString *)host port:(uint16_t)port;

- (instancetype)initWithProxyHost:(NSString *)host port:(uint16_t)port username:(NSString *)username password:(NSString *)password;

@end


@interface SSHKitConnectorSOCKS4 : SSHKitConnectorProxy

@end


@interface SSHKitConnectorSOCKS4A : SSHKitConnectorSOCKS4

@end

@interface SSHKitConnectorSOCKS5 : SSHKitConnectorProxy

@end

@interface SSHKitConnectorHTTPS : SSHKitConnectorProxy

@end
