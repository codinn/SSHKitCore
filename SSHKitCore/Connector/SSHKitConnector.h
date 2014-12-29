//
//  SSHKitConnector.h
//  SSHKitCore
//
//  Created by Yang Yubo on 12/23/14.
//
//

#import <Foundation/Foundation.h>

@interface SSHKitConnector : NSObject

- (instancetype)initWithTimeout:(NSTimeInterval)timeout;

@property (readonly) int socketFD;

// connect to target

- (BOOL)connectToTarget:(NSString *)host onPort:(uint16_t)port error:(NSError **)errPtr;

- (void)disconnect;

@end
