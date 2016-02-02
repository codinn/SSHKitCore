//
//  SSHKitHelpers.h
//  SSHKitCore
//
//  Created by Yang Yubo on 2/2/16.
//
//

#import <Foundation/Foundation.h>
#import "SSHKitCoreCommon.h"

@interface SSHKitForwardRequest : NSObject

- (instancetype)initWithListenHost:(NSString *)host port:(uint16_t)port completionHandler:(SSHKitRequestRemoteForwardCompletionBlock)completionHandler;

@property (readonly, copy) NSString    *listenHost;
@property (readonly)       uint16_t    listenPort;
@property (readonly, strong)       SSHKitRequestRemoteForwardCompletionBlock completionHandler;

@end
