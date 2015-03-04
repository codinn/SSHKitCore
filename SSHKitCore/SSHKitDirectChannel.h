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

- (void)setPeerHost:(NSString *)host port:(NSUInteger)port;

@property (readonly) NSString      *host;
@property (readonly) NSUInteger    port;

@end
