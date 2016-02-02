//
//  SSHKitForwardChannel.h
//  SSHKitCore
//
//  Created by Yang Yubo on 2/2/16.
//
//

#import <SSHKitCore/SSHKitCore.h>

// forwarded-tcpip

@interface SSHKitForwardChannel : SSHKitChannel

/** tcpip-forward channel properties */
@property (readonly) NSInteger destinationPort;

@end
