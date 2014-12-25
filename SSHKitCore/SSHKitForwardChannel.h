//
//  SSHKitForwardChannel.h
//  SSHKitCore
//
//  Created by Yang Yubo on 12/6/14.
//
//

#import <SSHKitCore/SSHKitChannel.h>

@interface SSHKitForwardChannel : SSHKitChannel

@property (readonly) NSInteger destinationPort;

@end
