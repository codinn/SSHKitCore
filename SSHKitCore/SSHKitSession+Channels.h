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

- (SSHKitForwardChannel *)openForwardChannel;

- (void)enqueueForwardRequestWithListenHost:(NSString *)host listenPort:(uint16_t)port completionHandler:(SSHKitRequestRemoteForwardCompletionBlock)completionHandler;

- (SSHKitShellChannel *)openShellChannelWithTerminalType:(NSString *)type columns:(NSInteger)columns rows:(NSInteger)rows delegate:(id<SSHKitShellChannelDelegate>)aDelegate;

// @internal
- (void)doSendForwardRequest;

@end
