//
//  SSHKitDirectChannel.h
//  SSHKitCore
//
//  Created by Yang Yubo on 2/2/16.
//
//

#import <SSHKitCore/SSHKitCore.h>

// direct-tcpip

@interface SSHKitDirectChannel : SSHKitChannel

/** direct-tcpip channel properties */
@property (readonly) NSString      *targetHost;
@property (readonly) NSUInteger    targetPort;

@end
