//
//  SSHKitSessionChannel.h
//  SSHKitCore
//
//  Created by Yang Yubo on 2/2/16.
//
//
#import <SSHKitCore/SSHKitCoreCommon.h>
#import "SSHKitChannel.h"

@interface SSHKitSessionChannel : SSHKitChannel

- (void)changePtySizeToColumns:(NSInteger)columns rows:(NSInteger)rows;

@property (readonly, nonatomic) NSInteger  shellColumns;
@property (readonly, nonatomic) NSInteger  shellRows;

@end
