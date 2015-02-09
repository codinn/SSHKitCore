//
//  SSHKitDirectChannel.h
//  SSHKit
//
//  Created by Yang Yubo on 10/29/14.
//
//
#import <SSHKitCore/SSHKitCoreCommon.h>
#import <SSHKitCore/SSHKitChannel.h>

@interface SSHKitDirectChannel : SSHKitChannel

@property NSString      *host;
@property NSUInteger    port;

@end
