//
//  SSHKitSFTP.h
//  SSHKitCore
//
//  Created by vicalloy on 8/26/15.
//
//

#import <Foundation/Foundation.h>
#import "SSHKitCoreCommon.h"

@class SSHKitSession;
@class SSHKitChannel;
@class SSHKitSFTPFile;
@class SSHKitSFTPRequest;  // define in SSHKitExtras

@interface SSHKitSFTPChannel : NSObject <SSHKitChannelDelegate>

@property (nonatomic, weak) id<SSHKitChannelDelegate> delegate;
@property (nonatomic, weak, readonly) SSHKitSession* sshSession;
@property (nonatomic, weak, readonly) SSHKitChannel* sshChannel;

+ (void)freeSFTPAttributes:(sshkit_sftp_attributes)attributes;
- (instancetype)initWithSession:(SSHKitSession *)session delegate:(id<SSHKitChannelDelegate>)delegate;
- (void)close;
- (SSHKitSFTPFile *)openDirectory:(NSString *)path;
- (SSHKitSFTPFile *)openFile:(NSString *)path;

@end