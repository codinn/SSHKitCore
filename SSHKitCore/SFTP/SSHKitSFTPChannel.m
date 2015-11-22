//
//  SSHKitSFTP.m
//  SSHKitCore
//
//  Created by vicalloy on 8/26/15.
//
//

#import "SSHKitCore+Protected.h"
#import "SSHKitChannel.h"

@interface SSHKitSFTPChannel()
@end

@implementation SSHKitSFTPChannel

+ (void)freeSFTPAttributes:(sshkit_sftp_attributes)attributes {
    sftp_attributes_free(attributes);
}

- (int)getLastSFTPError {
    return sftp_get_error(self.rawSFTPSession);
}

- (void)channel:(SSHKitChannel *)channel didReadStdoutData:(NSData *)data {
    if (self.stage != SSHKitChannelStageReadWrite) {
        return;
    }
    for (SSHKitSFTPFile *file in _remoteFiles) {
        [file channel:self didReadStdoutData:data];
    }
}

- (void)_doProcess_del {
    [super _doProcess];
    if (self.stage != SSHKitChannelStageReadWrite) {
        return;
    }
    for (SSHKitSFTPFile *file in _remoteFiles) {
        [file _doProcess];
    }
}

- (BOOL)isFileExist:(NSString *)path {
    SSHKitSFTPFile* file = [[SSHKitSFTPFile alloc]init:self path:path isDirectory:NO];
    // TODO handle error
    return [file isExist];
}

- (SSHKitSFTPFile *)openDirectory:(NSString *)path {
    SSHKitSFTPFile* directory = [[SSHKitSFTPFile alloc]init:self path:path isDirectory:YES];
    // TODO handle error
    [directory open];
    return directory;
}

- (SSHKitSFTPFile *)openFile:(NSString *)path {
    SSHKitSFTPFile* file = [[SSHKitSFTPFile alloc]init:self path:path isDirectory:NO];
    // TODO handle error
    [file open];
    return file;
}

- (SSHKitSFTPFile *)openFile:(NSString *)path accessType:(int)accessType mode:(unsigned long)mode {
    SSHKitSFTPFile* file = [[SSHKitSFTPFile alloc]init:self path:path isDirectory:NO];
    // TODO handle error
    [file openFile:accessType mode:mode];
    return file;
}

- (SSHKitSFTPFile *)openFileForWrite:(NSString *)path shouldResume:(BOOL)shouldResume mode:(unsigned long)mode {
    SSHKitSFTPFile* file = [[SSHKitSFTPFile alloc]init:self path:path isDirectory:NO];
    // TODO handle error
    [file openFileForWrite:shouldResume mode:mode];
    return file;
}

- (NSString *)canonicalizePath:(NSString *)path {
    return [NSString stringWithUTF8String:sftp_canonicalize_path(self.rawSFTPSession, [path UTF8String])
            ];
}

- (int)chmod:(NSString *)filePath mode:(unsigned long)mode {
    return sftp_chmod(self.rawSFTPSession, [filePath UTF8String], mode);
}

- (NSMutableArray *)remoteFiles {
    if (_remoteFiles == nil) {
        _remoteFiles = [@[]mutableCopy];
    }
    return _remoteFiles;
}

@end
