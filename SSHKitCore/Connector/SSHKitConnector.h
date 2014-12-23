//
//  SSHKitConnector.h
//  SSHKitCore
//
//  Created by Yang Yubo on 12/23/14.
//
//

#import <Foundation/Foundation.h>

NSData * CSConnectLocalResolveHost(NSString *host, uint16_t port, NSError **errPtr);

@interface SSHKitConnector : NSObject

- (instancetype)initWithTimeout:(NSTimeInterval)timeout;

// connect to target

- (BOOL)connectToTarget:(NSString *)host onPort:(uint16_t)port error:(NSError **)errPtr;

- (void)disconnect;

- (int)dupSocketFD;

@end
