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

+ (instancetype)keyPairFromFilePath:(NSString *)path withAskPass:(SSHKitAskPassBlock)askPass error:(NSError **)errPtr;

+ (instancetype)keyPairFromBase64:(NSString *)base64 withAskPass:(SSHKitAskPassBlock)askPass error:(NSError **)errPtr;

@end
