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

/**
 * @brief Sends the "tcpip-forward" global request to ask the server to begin
 *        listening for inbound connections.
 *
 * @param[in]  host     The address to bind to on the server. Pass NULL to bind
 *                      to all available addresses on all protocol families
 *                      supported by the server.
 *
 * @param[in]  port     The port to bind to on the server. Pass 0 to ask the
 *                      server to allocate the next available unprivileged port
 *                      number
 *
 * @param[in]  block    A block will run after request complete
 **/
- (void)requestListeningOnAddress:(NSString *)host port:(uint16_t)port completion:(SSHKitListeningRequestCompletionBlock)block;

- (SSHKitShellChannel *)openShellChannelWithTerminalType:(NSString *)type columns:(NSInteger)columns rows:(NSInteger)rows delegate:(id<SSHKitShellChannelDelegate>)aDelegate;

- (SSHKitSFTPChannel *)openSFTPChannel:(id<SSHKitChannelDelegate>)aDelegate;

// @internal
- (void)doSendForwardRequest;

// @internal
- (SSHKitForwardChannel *)doTryOpenForwardChannel;

@end
