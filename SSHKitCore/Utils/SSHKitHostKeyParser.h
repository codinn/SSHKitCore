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

- (NSError *)parseFromSession:(SSHKitSession *)session;
- (NSError *)parseFromBase64:(NSString *)base64 type:(SSHKitHostKeyType)type;

@property (nonatomic, readonly) SSHKitHostKeyType   type;
@property (nonatomic, readonly) NSString            *typeName;
@property (nonatomic, readonly) NSString            *base64;
@property (nonatomic, readonly) NSString            *fingerprint;

@end
