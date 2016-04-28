//
//  SSHKitSession+Channels.h
//  SSHKitCore
//
//  Created by Yang Yubo on 2/2/16.
//
//

#import <Foundation/Foundation.h>
#import "SSHKitCoreCommon.h"
#import "SSHKitSession.h"

@interface SSHKitSession (Channels)

// -----------------------------------------------------------------------------
#pragma mark Creating Channels
// -----------------------------------------------------------------------------

- (SSHKitDirectChannel *)openDirectChannelWithTargetHost:(NSString *)host port:(NSUInteger)port delegate:(id<SSHKitChannelDelegate>)aDelegate;

- (void)requestForwardChannelWithListenHost:(NSString *)host port:(uint16_t)port completion:(SSHKitForwardRequestCompletionBlock)block;

- (SSHKitShellChannel *)openShellChannelWithTerminalType:(NSString *)type columns:(NSInteger)columns rows:(NSInteger)rows delegate:(id<SSHKitShellChannelDelegate>)aDelegate;

- (SSHKitSFTPChannel *)openSFTPChannel:(id<SSHKitChannelDelegate>)aDelegate;

// @internal
- (void)doSendForwardRequest;

// @internal
- (SSHKitForwardChannel *)doTryOpenForwardChannel;

@end
