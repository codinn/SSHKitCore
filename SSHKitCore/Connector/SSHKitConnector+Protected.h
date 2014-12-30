//
//  SSHKitConnect+Protected.h
//  sshproxy
//
//  Created by Yang Yubo on 11/8/14.
//  Copyright (c) 2014 Codinn. All rights reserved.
//

#import <Foundation/Foundation.h>
#import "CoSocket.h"

@interface SSHKitConnectorProxy()

// proxy settings

@property (readwrite) NSString *proxyHost;
@property (readwrite) uint16_t proxyPort;

@property (readwrite) NSString *targetHost;
@property (readwrite) uint16_t targetPort;

@property (readwrite) NSString *proxyUsername;
@property (readwrite) NSString *proxyPassword;

@end
