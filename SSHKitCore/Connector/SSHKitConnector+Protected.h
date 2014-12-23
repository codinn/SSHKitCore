//
//  SSHKitConnect+Protected.h
//  sshproxy
//
//  Created by Yang Yubo on 11/8/14.
//  Copyright (c) 2014 Codinn. All rights reserved.
//

#import <Foundation/Foundation.h>
#import "CoSocket.h"

@interface SSHKitConnector() {
    @protected
    CoSocket *_coSocket;
}

@property (readwrite) NSTimeInterval timeout;

@property (readwrite) NSString *targetHost;
@property (readwrite) uint16_t targetPort;
@end

@interface SSHKitConnectorProxy()

@property (readwrite) NSString *proxyHost;
@property (readwrite) uint16_t proxyPort;

@property (readwrite) NSString *proxyUsername;
@property (readwrite) NSString *proxyPassword;

@end
