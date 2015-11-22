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
- (BOOL)isFileExist:(NSString *)path;
- (SSHKitSFTPFile *)openDirectory:(NSString *)path;
- (SSHKitSFTPFile *)openFile:(NSString *)path;
- (SSHKitSFTPFile *)openFileForWrite:(NSString *)path shouldResume:(BOOL)shouldResume;

@end