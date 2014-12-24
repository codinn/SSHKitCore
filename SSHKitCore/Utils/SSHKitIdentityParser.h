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

- (instancetype)initWithIdentityPath:(NSString *)path passphraseHandler:(SSHKitAskPassphrasePrivateKeyBlock)passphraseHandler;

- (NSError *)parse;

@end
