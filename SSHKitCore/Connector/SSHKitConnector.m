//
//  SSHKitConnector.m
//  SSHKitCore
//
//  Created by Yang Yubo on 12/23/14.
//
//

#import "SSHKitConnector.h"
#import "SSHKitConnectorProxy.h"
#import "CoSocket.h"
#import "CoSOCKSMessage.h"
#import "SSHKitConnector+Protected.h"

@implementation SSHKitConnector

- (instancetype)initWithTimeout:(NSTimeInterval)timeout
{
    if((self = [super init])) {
        self.timeout = timeout;
    }
    
    return self;
}

- (void)dealloc
{
    [self disconnect];
}

- (int)socketFD
{
    if (_coSocket) {
        return _coSocket.socketFD;
    }
    
    return -1;
}

- (BOOL)connectToTarget:(NSString *)host onPort:(uint16_t)port error:(NSError **)errPtr
{
    self.targetHost = host;
    self.targetPort = port;
    
    _coSocket = [[CoSocket alloc] init];
    
    return [_coSocket connectToHost:self.targetHost onPort:self.targetPort withTimeout:self.timeout error:errPtr];
}


- (void)disconnect
{
    if (_coSocket) {
        [_coSocket disconnect];
    }
    
    _coSocket = nil;
}

@end
