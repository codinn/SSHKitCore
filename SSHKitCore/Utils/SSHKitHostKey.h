//
//  SSHKitHostKey.h
//  SSHKitCore
//
//  Created by Yang Yubo on 12/24/14.
//
//

#import <Foundation/Foundation.h>
#import "SSHKitCore.h"

@class SSHKitSession;

@interface SSHKitHostKey : NSObject

+ (instancetype)hostKeyFromBase64:(NSString *)base64 withType:(NSInteger)type error:(NSError **)errPtr;

@property (nonatomic, readonly) NSInteger           keyType;
@property (nonatomic, readonly) NSString            *typeName;
@property (nonatomic, readonly) NSString            *base64;
@property (nonatomic, readonly) NSString            *fingerprint;

@end

/* 
 * name can be one of following values:
 *  - rsa1, ssh-rsa1
 *  - rsa, ssh-rsa
 *  - dsa, ssh-dss
 *  - ecdsa, ssh-ecdsa, ecdsa-sha2-nistp256, ecdsa-sha2-nistp384, ecdsa-sha2-nistp521
 *  - ssh-ed25519
 */
NSInteger SSHKitHostKeyTypeFromName(NSString *name);
