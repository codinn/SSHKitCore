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
- (int)getLastSFTPError;
- (BOOL)isFileExist:(NSString *)path;
- (SSHKitSFTPFile *)getDirectory:(NSString *)path;
- (SSHKitSFTPFile *)getFile:(NSString *)path;
- (SSHKitSFTPFile *)openDirectory:(NSString *)path;
- (SSHKitSFTPFile *)openFile:(NSString *)path;
- (SSHKitSFTPFile *)openFile:(NSString *)path accessType:(int)accessType mode:(unsigned long)mode;
- (SSHKitSFTPFile *)openFileForWrite:(NSString *)path shouldResume:(BOOL)shouldResume mode:(unsigned long)mode;
- (NSString *)canonicalizePath:(NSString *)path;
- (int)chmod:(NSString *)filePath mode:(unsigned long)mode;
- (int)mkdir:(NSString *)directoryPath mode:(unsigned long)mode;

@end