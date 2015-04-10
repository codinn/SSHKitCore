//
//  SSHKitPrivateKeyParser.h
//  SSHKitCore
//
//  Created by Yang Yubo on 12/24/14.
//
//

#import <Foundation/Foundation.h>
#import "SSHKitCore.h"

@interface SSHKitPrivateKeyParser : NSObject

@property (nonatomic) NSString *passpharse;
@property (nonatomic, readonly) SSHKitHostKeyParser *publicKeyParser;

+ (instancetype)parserFromFilePath:(NSString *)path withPassphraseHandler:(SSHKitAskPassphrasePrivateKeyBlock)passphraseHandler error:(NSError **)errPtr;

+ (instancetype)parserFromBase64:(NSString *)base64 withPassphraseHandler:(SSHKitAskPassphrasePrivateKeyBlock)passphraseHandler error:(NSError **)errPtr;

+ (instancetype)generate:(SSHKitKeyType) type parameter:(int)param error:(NSError **)errPtr;

- (void)exportPrivateKey:(NSString *)path passpharse:(NSString *)passpharse error:(NSError **)errPtr;

- (NSData *)exportBlob;

@end
