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
@class SSHKitSFTPFile;

@interface SSHKitSFTPChannel : NSObject

@property (nonatomic, weak, readonly) id<SSHKitSFTPDelegate> delegate;
@property (nonatomic, weak, readonly) SSHKitSession* sshSession;

+ (void)freeSFTPAttributes:(sshkit_sftp_attributes)attributes;
- (instancetype)initWithDelegate:(id<SSHKitSFTPDelegate>)delegate;
- (BOOL)initSFTP:(SSHKitSession *)session;
- (void)close;
- (SSHKitSFTPFile *)openDirectory:(NSString *)path;

@end

@protocol SSHKitSFTPDelegate <NSObject>
@optional
- (NSString *)sftp:(SSHKitSFTPChannel *)sftp didInitWithSession:(SSHKitSession *)session;
@end