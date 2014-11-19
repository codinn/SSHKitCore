//
//  SSHKitDirectTCPIPChannel.h
//  SSHKit
//
//  Created by Brant Young on 10/29/14.
//
//

#import "SSHKitChannel.h"

@interface SSHKitDirectTCPIPChannel : SSHKitChannel

@property NSString      *host;
@property NSUInteger    port;

@end
