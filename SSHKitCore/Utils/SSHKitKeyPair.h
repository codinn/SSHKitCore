//
//  SSHKitKeyPair.h
//  SSHKitCore
//
//  Created by Yang Yubo on 12/24/14.
//
//

#import <Foundation/Foundation.h>
#import "SSHKitCore.h"

@interface SSHKitKeyPair : NSObject

- (instancetype)initWithKeyPath:(NSString *)path withAskPass:(SSHKitAskPassBlock)askPass error:(NSError **)errPtr;

- (instancetype)initWithKeyBase64:(NSString *)base64 withAskPass:(SSHKitAskPassBlock)askPass error:(NSError **)errPtr;

@end
