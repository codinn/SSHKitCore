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

- (SSHKitSFTPFile *)openDirectory:(NSString *)path errorPtr:(NSError **)errorPtr;
- (SSHKitSFTPFile *)openFile:(NSString *)path errorPtr:(NSError **)errorPtr;
- (SSHKitSFTPFile *)openFile:(NSString *)path accessType:(int)accessType mode:(unsigned long)mode errorPtr:(NSError **)errorPtr;
- (SSHKitSFTPFile *)openFileForWrite:(NSString *)path shouldResume:(BOOL)shouldResume mode:(unsigned long)mode errorPtr:(NSError **)errorPtr;

- (NSString *)canonicalizePath:(NSString *)path errorPtr:(NSError **)errorPtr;
- (NSError *)chmod:(NSString *)filePath mode:(unsigned long)mode;
- (NSError *)rename:(NSString *)original newName:(NSString *)newName;
- (NSError *)mkdir:(NSString *)directoryPath mode:(unsigned long)mode;
- (NSError *)rmdir:(NSString *)directoryPath;
- (NSError *)unlink:(NSString *)filePath;

@end
