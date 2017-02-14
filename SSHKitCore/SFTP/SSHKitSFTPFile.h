//
//  SSHKitSFTPDirectory.h
//  SSHKitCore
//
//  Created by vicalloy on 8/28/15.
//
//

#import <Foundation/Foundation.h>
#import "SSHKitCoreCommon.h"
#import "SSHKitChannel.h"

#define MAX_XFER_BUF_SIZE 16384-13

@class SSHKitSFTPChannel;

@interface SSHKitSFTPFile : NSObject

/**
 Property that stores the name of the underlaying file.
 Note that the file may also be a directory.
 */
@property (nonatomic) NSString *filename;

@property (nonatomic) NSString *fullFilename;

/** Property that declares whether the file is a directory or a regular file */
@property (nonatomic, readonly) BOOL isDirectory;

@property (nonatomic, readonly) BOOL isLink;

@property (nonatomic, readonly) NSDate *creationDate;

/** Returns the last modification date of the file */
@property (nonatomic, readonly) NSDate *modificationDate;

/** Returns the date of the last access to the file */
@property (nonatomic, readonly) NSDate *lastAccess;

/** Property that returns the file size in bytes */
@property (nonatomic, readonly) NSNumber *fileSize;

/** Returns the numeric identifier of the user that is the owner of the file */
@property (nonatomic, readonly) unsigned long ownerUserID;

/** Returns the numeric identifier of the group that is the owner of the file */
@property (nonatomic, readonly) unsigned long ownerGroupID;

@property (nonatomic, readonly) NSString *ownerUserName;

@property (nonatomic, readonly) NSString *ownerGroupName;

/** Returns the file permissions in symbolic notation. E.g. drwxr-xr-x */
@property (nonatomic, readonly) NSString *permissions;

@property (nonatomic) unsigned long posixPermissions;

@property (nonatomic, readonly) char fileTypeLetter;

@property (nonatomic, readonly) NSString *kindOfFile;

/** Returns the user defined flags for the file */
@property (nonatomic, readonly) u_long flags;

@property (nonatomic, readonly) SSHKitSFTPChannel *sftp;
@property (nonatomic, readonly) BOOL directoryEof;

@property (nonatomic, readonly) SSHKitSFTPFile *symlinkTarget;

+ (instancetype)openDirectory:(SSHKitSFTPChannel *)sftpChannel path:(NSString *)path errorPtr:(NSError **)errorPtr;
+ (instancetype)openFile:(SSHKitSFTPChannel *)sftpChannel path:(NSString *)path errorPtr:(NSError **)errorPtr;
+ (instancetype)openFile:(SSHKitSFTPChannel *)sftpChannel path:(NSString *)path accessType:(int)accessType mode:(unsigned long)mode errorPtr:(NSError **)errorPtr;
+ (instancetype)openFileForWrite:(SSHKitSFTPChannel *)sftpChannel path:(NSString *)path shouldResume:(BOOL)shouldResume mode:(unsigned long)mode errorPtr:(NSError **)errorPtr;


- (instancetype)init:(SSHKitSFTPChannel *)sftp path:(NSString *)path isDirectory:(BOOL)isDirectory;
- (void)close;
- (NSArray *)listDirectory:(SSHKitSFTPListDirFilter)filter;
- (void)seek64:(unsigned long long)offset;
- (int)read:(char *)buffer errorPtr:(NSError **)errorPtr;
- (void)asyncReadFile:(unsigned long long)offset
        readFileBlock:(SSHKitSFTPClientReadFileBlock)readFileBlock
        progressBlock:(SSHKitSFTPClientProgressBlock)progressBlock
        fileTransferSuccessBlock:(SSHKitSFTPClientSuccessBlock)fileTransferSuccessBlock
fileTransferFailBlock:(SSHKitSFTPClientFailureBlock)fileTransferFailBlock;
- (void)cancelAsyncReadFile;
-(long)write:(const void *)buffer size:(long)size errorPtr:(NSError **)errorPtr;

- (NSError *)updateSymlinkTargetStat;  // get symlink's tagert info

@end
