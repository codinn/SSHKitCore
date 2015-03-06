//
//  SSHKitHostKeyParser.h
//  SSHKitCore
//
//  Created by Yang Yubo on 12/24/14.
//
//

#import <Foundation/Foundation.h>
#import "SSHKitCore.h"

@class SSHKitSession;

@interface SSHKitHostKeyParser : NSObject

+ (instancetype)parserFromSession:(SSHKitSession *)session error:(NSError **)errPtr;
+ (instancetype)parserFromBase64:(NSString *)base64 withType:(NSInteger)type error:(NSError **)errPtr;

@property (nonatomic, readonly) NSInteger           keyType;
@property (nonatomic, readonly) NSString            *typeName;
@property (nonatomic, readonly) NSString            *base64;
@property (nonatomic, readonly) NSString            *fingerprint;

+ (NSString *)nameForKeyType:(NSInteger)keyType;

@end
