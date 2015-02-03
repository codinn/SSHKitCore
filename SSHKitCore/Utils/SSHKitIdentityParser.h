//
//  SSHKitIdentityParser.h
//  SSHKitCore
//
//  Created by Yang Yubo on 12/24/14.
//
//

#import <Foundation/Foundation.h>
#import "SSHKitCore.h"

@interface SSHKitIdentityParser : NSObject

+ (instancetype)parserFromIdentityPath:(NSString *)path withPassphraseHandler:(SSHKitAskPassphrasePrivateKeyBlock)passphraseHandler error:(NSError **)errPtr;

+ (instancetype)parserFromIdentityBase64:(NSString *)base64 withPassphraseHandler:(SSHKitAskPassphrasePrivateKeyBlock)passphraseHandler error:(NSError **)errPtr;

@end
