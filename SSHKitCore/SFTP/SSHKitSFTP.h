//
//  SSHKitSFTP.h
//  SSHKitCore
//
//  Created by vicalloy on 8/26/15.
//
//

#import <Foundation/Foundation.h>
#import "SSHKitCoreCommon.h"

@protocol SSHKitSFTPDelegate;
@class SSHKitSession;
@class SSHKitSFTPDirectory;

@interface SSHKitSFTP : NSObject

@property (nonatomic, weak, readonly) id<SSHKitSFTPDelegate> delegate;
@property (nonatomic, weak, readonly) SSHKitSession* sshSession;

+ (void)FreeSFTPAttributes:(sshkit_sftp_attributes)attributes;
- (instancetype)initWithDelegate:(id<SSHKitSFTPDelegate>)delegate;
- (BOOL)initSFTP:(SSHKitSession *)session;
- (void)close;
- (SSHKitSFTPDirectory *)openDirectory:(NSString *)path;

@end

@protocol SSHKitSFTPDelegate <NSObject>
@optional
@end
