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

@interface SSHKitSFTPChannel : SSHKitChannel
@property (nonatomic) NSMutableArray *remoteFiles;
+ (void)freeSFTPAttributes:(sshkit_sftp_attributes)attributes;
- (SSHKitSFTPFile *)openDirectory:(NSString *)path;
- (SSHKitSFTPFile *)openFile:(NSString *)path;

@end