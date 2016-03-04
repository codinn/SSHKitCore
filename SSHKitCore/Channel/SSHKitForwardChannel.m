//
//  SSHKitForwardChannel.m
//  SSHKitCore
//
//  Created by Yang Yubo on 2/2/16.
//
//

#import "SSHKitForwardChannel.h"
#import "SSHKitSession.h"
#import "SSHKitCore+Protected.h"

@implementation SSHKitForwardChannel

- (instancetype)initWithSession:(SSHKitSession *)session destinationPort:(NSUInteger)port {
    if (self = [super initWithSession:session delegate:nil]) {
        _destinationPort = port;
    }
    
    return self;
}

- (void)doOpen {
    // do nothing, forwarded-tcpip channel is created when remote server response a global channel request
}

@end
