//
//  SSHKitSFTPDirectory.m
//  SSHKitCore
//
//  Created by vicalloy on 8/28/15.
//
//

#import "SSHKitSFTPFile.h"
#import "SSHKitCore+Protected.h"
#import <sys/stat.h>

#define CONCURRENT_REQ_COUNT 16

typedef NS_ENUM(NSInteger, SSHKitFileStage)  {
    SSHKitFileStageNone = 0,
    SSHKitFileStageReadingFile,
};

@interface SSHKitSFTPFile () {
    dispatch_group_t _readChunkGroup;
    unsigned long long _totalBytes;
    dispatch_queue_t _readChunkQueue;
    int _requestIds[CONCURRENT_REQ_COUNT];
}

@property (nonatomic, readwrite) BOOL isDirectory;
@property (nonatomic, readwrite) BOOL isLink;
@property (nonatomic, strong) NSDate *creationDate;
@property (nonatomic, strong) NSDate *modificationDate;
@property (nonatomic, strong) NSDate *lastAccess;
@property (nonatomic, strong) NSNumber *fileSize;
@property (nonatomic, readwrite) unsigned long ownerUserID;
@property (nonatomic, readwrite) unsigned long ownerGroupID;
@property (nonatomic, strong) NSString *ownerUserName;
@property (nonatomic, strong) NSString *ownerGroupName;
@property (nonatomic, strong) NSString *permissions;
@property (nonatomic, readwrite) u_long flags;

@property (nonatomic) SSHKitFileStage stage;
@property (nonatomic, copy) SSHKitSFTPClientReadFileBlock readFileBlock;
@property (nonatomic, copy) SSHKitSFTPClientProgressBlock progressBlock;
@property (nonatomic, copy) SSHKitSFTPClientSuccessBlock fileTransferSuccessBlock;
@property (nonatomic, copy) SSHKitSFTPClientFailureBlock fileTransferFailBlock;
// @property (nonatomic) SSHKitFileStage readBytesLength;
@end

@implementation SSHKitSFTPFile

- (instancetype)init:(SSHKitSFTPChannel *)sftp path:(NSString *)path isDirectory:(BOOL)isDirectory {
    // https://github.com/dleehr/DLSFTPClient/blob/master/
    if ((self = [super init])) {
        _readChunkGroup = dispatch_group_create();
        _readChunkQueue = dispatch_queue_create("com.codinn.readchunk", DISPATCH_QUEUE_SERIAL);
        self.isDirectory = isDirectory;
        self.fullFilename = path;
        self.filename = [path lastPathComponent];
        _sftp = sftp;
    }
    return self;
}

- (instancetype)initWithSFTPAttributes:(sftp_attributes)fileAttributes parentPath:(NSString *)parentPath {
    if ((self = [super init])) {
        [self populateValuesFromSFTPAttributes:fileAttributes parentPath:parentPath];
    }
    return self;
}

+ (instancetype)initDirectory:(SSHKitSFTPChannel *)sftpChannel path:(NSString *)path {
    return [[SSHKitSFTPFile alloc]init:sftpChannel path:path isDirectory:YES];
}

+ (instancetype)initFile:(SSHKitSFTPChannel *)sftpChannel path:(NSString *)path {
    return [[SSHKitSFTPFile alloc]init:sftpChannel path:path isDirectory:NO];
}

+ (instancetype)openDirectory:(SSHKitSFTPChannel *)sftpChannel path:(NSString *)path errorPtr:(NSError **)errorPtr {
    
    SSHKitSFTPFile* directory = [SSHKitSFTPFile initDirectory:sftpChannel path:path];
    __block NSError *error;

    [sftpChannel.session dispatchSyncOnSessionQueue:^{
        error = [SSHKitSFTPFile returnErrorIfNotConnected:sftpChannel.session];
        if (error) {
            return_from_block;
        }

        error = [directory open];
        if (errorPtr) {
            *errorPtr = error;
        }
    }];

    if (error) {
        return nil;
    }

    return directory;
}

+ (instancetype)openFile:(SSHKitSFTPChannel *)sftpChannel path:(NSString *)path errorPtr:(NSError **)errorPtr {
    SSHKitSFTPFile* file = [SSHKitSFTPFile initFile:sftpChannel path:path];
    __block NSError *error;

    [sftpChannel.session dispatchSyncOnSessionQueue:^{
        error = [SSHKitSFTPFile returnErrorIfNotConnected:sftpChannel.session];
        if (error) {
            return_from_block;
        }

        error = [file open];
        if (errorPtr) {
            *errorPtr = error;
        }
    }];

    if (error) {
        return nil;
    }

    return file;
}

+ (instancetype)openFile:(SSHKitSFTPChannel *)sftpChannel path:(NSString *)path accessType:(int)accessType mode:(unsigned long)mode errorPtr:(NSError **)errorPtr {
    SSHKitSFTPFile* file = [SSHKitSFTPFile initFile:sftpChannel path:path];
    __block NSError *error;

    [sftpChannel.session dispatchSyncOnSessionQueue:^{
        error = [SSHKitSFTPFile returnErrorIfNotConnected:sftpChannel.session];
        if (error) {
            return_from_block;
        }

        error = [file openFile:accessType mode:mode];
        if (errorPtr) {
            *errorPtr = error;
        }
    }];

    if (error) {
        return nil;
    }

    return file;
}

+ (instancetype)openFileForWrite:(SSHKitSFTPChannel *)sftpChannel path:(NSString *)path shouldResume:(BOOL)shouldResume mode:(unsigned long)mode errorPtr:(NSError **)errorPtr {
    SSHKitSFTPFile* file = [SSHKitSFTPFile initFile:sftpChannel path:path];
    __block NSError *error;
    
    [sftpChannel.session dispatchSyncOnSessionQueue:^{
        error = [SSHKitSFTPFile returnErrorIfNotConnected:sftpChannel.session];
        if (error) {
            return_from_block;
        }

        error = [file openFileForWrite:shouldResume mode:mode];
        if (errorPtr) {
            *errorPtr = error;
        }
    }];

    if (error) {
        return nil;
    }

    return file;
}

#pragma mark - open file/directory

- (NSError *)openDirectory {
    __weak SSHKitSFTPFile *weakSelf = self;
    __block NSError *error;

    [self.sftp.session dispatchSyncOnSessionQueue:^{
        __strong SSHKitSFTPFile *strongSelf = weakSelf;
        error = [weakSelf returnErrorIfNotConnected];
        if (error) {
            return_from_block;
        }

        strongSelf->_rawDirectory = sftp_opendir(strongSelf.sftp.rawSFTPSession, [strongSelf.fullFilename UTF8String]);
    }];

    if (error) {
        return error;
    }

    if (self.rawDirectory == NULL) {
        return self.sftp.libsshSFTPError;
    }
    return nil;
}

- (NSError *)updateStat {
    if (!self.sftp.session.isConnected) {
        return [NSError errorWithDomain:SSHKitLibsshSFTPErrorDomain
                                        code:SSHKitSFTPErrorCodeGenericFailure
                                    userInfo: @{ NSLocalizedDescriptionKey : @"Session not connected" }];
    }
    __block sftp_attributes file_attributes = NULL;
    __weak SSHKitSFTPFile *weakSelf = self;
    __block NSError *error;

    [self.sftp.session dispatchSyncOnSessionQueue:^{
        error = [weakSelf returnErrorIfNotConnected];
        if (error) {
            return_from_block;
        }

        file_attributes = sftp_lstat(weakSelf.sftp.rawSFTPSession, [weakSelf.fullFilename UTF8String]);
    }];

    if (error) {
        return error;
    }

    if (file_attributes == NULL) {
        return self.sftp.session.libsshError;
    }
    [self populateValuesFromSFTPAttributes:file_attributes parentPath:nil];
    [SSHKitSFTPChannel freeSFTPAttributes:file_attributes];
    return nil;
}

- (NSError *)updateSymlinkTargetStat {
    __block sftp_attributes file_attributes = NULL;
    __weak SSHKitSFTPFile *weakSelf = self;
    __block NSError *error;
    NSString *symlinkTargetPath = [self.sftp readlink:self.fullFilename errorPtr:&error];
    if (error) {
        return error;
    }
    
    symlinkTargetPath = [self.sftp canonicalizePath:symlinkTargetPath errorPtr:&error];
    if (error) {
        return error;
    }
    
    [self.sftp.session dispatchSyncOnSessionQueue:^{
        error = [weakSelf returnErrorIfNotConnected];
        if (error) {
            return_from_block;
        }

        file_attributes = sftp_stat(weakSelf.sftp.rawSFTPSession, [weakSelf.fullFilename UTF8String]);
    }];

    if (error) {
        return error;
    }

    if (file_attributes == NULL) {
        return self.sftp.session.libsshError;
    }
    SSHKitSFTPFile *symlinkTarget = [[SSHKitSFTPFile alloc] initWithSFTPAttributes:file_attributes parentPath:nil];
    symlinkTarget.fullFilename = symlinkTargetPath;
    symlinkTarget.filename = [symlinkTargetPath lastPathComponent];
    self->_symlinkTarget = symlinkTarget;
    
    [SSHKitSFTPChannel freeSFTPAttributes:file_attributes];
    return nil;
}

- (NSError *)open {
    NSError *error = nil;
    if (self.isDirectory) {
        error = [self openDirectory];
    } else {
        error = [self openFile];
    }
    if (error) {
        return error;
    }
    
    // if updateStat not exec
    if (self.permissions == nil) {
        error = [self updateStat];
    }
    return error;
}

- (NSError *)openFile {
    return [self openFile:O_RDONLY mode:0];
}

- (NSError *)openFileForWrite:(BOOL)shouldResume mode:(unsigned long)mode {
    int oflag;
    if (shouldResume) {
        oflag =   O_APPEND
        | O_WRONLY
        | O_CREAT;
    } else {
        oflag =   O_WRONLY
        | O_CREAT
        | O_TRUNC;
    }
    NSError *error = [self openFile:oflag mode:mode];
    if (error) {
        return error;
    }
    if (self.permissions == nil) {
        error = [self updateStat];
        if (error) {
            [self close];
            return error;
        }
    }
    return nil;
}

- (NSError *)openFile:(int)accessType mode:(unsigned long)mode {
    // TODO create file
    // http://api.libssh.org/master/group__libssh__sftp.html#gab95cb5fe091efcc49dfa7729e4d48010
    __weak SSHKitSFTPFile *weakSelf = self;
    __block NSError *error;

    [self.sftp.session dispatchSyncOnSessionQueue:^{
        __strong SSHKitSFTPFile *strongSelf = weakSelf;
        error = [weakSelf returnErrorIfNotConnected];
        if (error) {
            return_from_block;
        }

        strongSelf->_rawFile = sftp_open(strongSelf.sftp.rawSFTPSession, [strongSelf.fullFilename UTF8String], accessType, mode);
    }];

    if (error) {
        return error;
    }

    if (_rawFile == NULL) {
        return self.sftp.session.libsshError;
    }
    return nil;
}

#pragma mark - SFTP Function warper

- (void)seek64:(unsigned long long)offset {
    __weak SSHKitSFTPFile *weakSelf = self;
    __block NSError *error;

    [self.sftp.session dispatchSyncOnSessionQueue:^{
        error = [weakSelf returnErrorIfNotConnected];
        if (error) {
            return_from_block;
        }

        sftp_seek64(weakSelf.rawFile, offset);
    }];
}

- (int)asyncReadBegin:(NSError **)errorPtr {
    __weak SSHKitSFTPFile *weakSelf = self;
    __block NSError *error;
    __block int requestNo = 0;

    [self.sftp.session dispatchSyncOnSessionQueue:^{
        __strong SSHKitSFTPFile *strongSelf = weakSelf;
        error = [weakSelf returnErrorIfNotConnected];
        if (error) {
            return_from_block;
        }

        requestNo = sftp_async_read_begin(strongSelf.rawFile, MAX_XFER_BUF_SIZE);
    }];

    if (requestNo < 0) {
        if (errorPtr) {
            if (error) {
                *errorPtr = error;
            } else {
                *errorPtr = self.sftp.libsshSFTPError;
            }
        }
    }

    return requestNo;
}

-(long)sftpWrite:(const void *)buffer size:(long)size errorPtr:(NSError **)errorPtr{
    __block long writeLength = 0;
    __weak SSHKitSFTPFile *weakSelf = self;
    __block NSError *error;
    
    [self.sftp.session dispatchSyncOnSessionQueue:^{
        // ssh_set_blocking(weakSelf.sftp.session.rawSession, 1);
        sftp_file_set_blocking(weakSelf.rawFile);
        error = [weakSelf returnErrorIfNotConnected];
        if (error) {
            return_from_block;
        }

        writeLength = sftp_write(weakSelf.rawFile, buffer, size);
    }];
    
    if (writeLength < 0) {
        if (errorPtr) {
            if (error) {
                *errorPtr = error;
            } else {
                *errorPtr = self.sftp.libsshSFTPError;
            }
        }
    }
    
    return writeLength;
}

#pragma mark - read/write file

- (long)read:(char *)buffer errorPtr:(NSError **)errorPtr {
    // [self dispatchSyncOnSessionQueue:
    // `sftp_async_read
    __block long result = -1;
    __weak SSHKitSFTPFile *weakSelf = self;
    __block NSError *error;
    
    [self.sftp.session dispatchSyncOnSessionQueue:^{
        error = [weakSelf returnErrorIfNotConnected];
        if (error) {
            return_from_block;
        }
        
        result = sftp_read(weakSelf.rawFile, buffer, MAX_XFER_BUF_SIZE);
    }];
    
    if (result < 0 && result != -2) {
        // Received a too big DATA packet from sftp server: 751 and asked for 8
        // printf("%d: %d\n", [self.sftp getLastSFTPError], result);
        if (errorPtr) {
            if (error) {
                *errorPtr = error;
            } else {
                *errorPtr = self.sftp.libsshSFTPError;
            }
        }
    }

    return result;
}

- (void)doFileTransferFail:(NSError *)error {
    __weak SSHKitSFTPFile *weakSelf = self;
    [self.sftp.session dispatchAsyncOnSessionQueue:^{
        __strong SSHKitSFTPFile *strongSelf = weakSelf;
        // if not in transfer mode, ignore it.
        if (strongSelf == nil) return;
        if (strongSelf.stage == SSHKitFileStageNone) {
            return;
        }
        
        strongSelf.stage = SSHKitFileStageNone;
        NSError *lastError = error;
        if (!lastError) {
            lastError = strongSelf.sftp.libsshSFTPError;
        }
        
        strongSelf.fileTransferFailBlock(lastError);
    }];
}

- (void)asyncBeginReadChunk {
    NSError *error;
    for (int i=0; i<CONCURRENT_REQ_COUNT; ++i){
        _requestIds[i] = 0;
    }
    
    self.stage = SSHKitFileStageReadingFile;
    
    unsigned long long beginReadBytes = _totalBytes;
    for (int i = 0; i < CONCURRENT_REQ_COUNT; i++) {
        if (beginReadBytes >= self.fileSize.unsignedLongLongValue) {
            return;
        }
        
        if (self.stage != SSHKitFileStageReadingFile) {
            return;
        }
        
        int requestNo = [self asyncReadBegin:&error];
        if (error) {
            [self doFileTransferFail:error];
            return;
        }
        _requestIds[i] = requestNo;
        beginReadBytes += MAX_XFER_BUF_SIZE;
    }
}

- (void)asyncReadChunk:(NSError **)errorPtr {
    BOOL isFinished = NO;
    NSError *error;
    
    char *buffer = malloc(sizeof(char) * MAX_XFER_BUF_SIZE);
    int i = 0;
    
    NSDate *lastUpdatedOn = [NSDate date];
    int readedBytesAfterLastUpdate = 0;
    
    if (_totalBytes == self.fileSize.longLongValue) {
        self.fileTransferSuccessBlock();
        isFinished = YES;
    }
    
    while(_totalBytes < self.fileSize.unsignedLongLongValue){
        @autoreleasepool {
            if (self.stage != SSHKitFileStageReadingFile) {
                free(buffer);
                self.progressBlock(readedBytesAfterLastUpdate, _totalBytes, self.fileSize.longLongValue);
                return;
            }
            int requestNo = _requestIds[i];
            int readBytes = [self asyncRead:requestNo buffer:buffer errorPtr:&error];
            
            if (!error) {
                _requestIds[i] = [self asyncReadBegin:&error];
            }
            
            if (error) {
                [self doFileTransferFail:error];
                if (errorPtr) {
                    *errorPtr = error;
                }
                free(buffer);
                self.progressBlock(readedBytesAfterLastUpdate, _totalBytes, self.fileSize.longLongValue);
                return;
            }
            
            if (readBytes > 0) {
                _totalBytes += readBytes;
                readedBytesAfterLastUpdate += readBytes;
                
                if ([lastUpdatedOn timeIntervalSinceNow] <= -0.1) {
                    self.progressBlock(readedBytesAfterLastUpdate, _totalBytes, self.fileSize.longLongValue);
                    lastUpdatedOn = [NSDate date];
                    readedBytesAfterLastUpdate = 0;
                }
                
                self.readFileBlock(buffer, readBytes);
            }
            
            if (readBytes == 0) {  // finished?
                isFinished = YES;
            }
            
            if (_totalBytes == self.fileSize.longLongValue) {
                self.fileTransferSuccessBlock();
                isFinished = YES;
            }
            
            if (isFinished) {
                free(buffer);
                self.progressBlock(readedBytesAfterLastUpdate, _totalBytes, self.fileSize.longLongValue);
                return;
            }
            
            i = (i+1) % CONCURRENT_REQ_COUNT;
        }
    }
    
    free(buffer);
    self.progressBlock(readedBytesAfterLastUpdate, _totalBytes, self.fileSize.longLongValue);
    return;
}

- (void)asyncReadFile:(unsigned long long)offset
        readFileBlock:(SSHKitSFTPClientReadFileBlock)readFileBlock
        progressBlock:(SSHKitSFTPClientProgressBlock)progressBlock
        fileTransferSuccessBlock:(SSHKitSFTPClientSuccessBlock)fileTransferSuccessBlock
        fileTransferFailBlock:(SSHKitSFTPClientFailureBlock)fileTransferFailBlock {
    _totalBytes = offset;

    self.readFileBlock = readFileBlock;
    self.progressBlock = progressBlock;
    self.fileTransferFailBlock = fileTransferFailBlock;
    self.fileTransferSuccessBlock = fileTransferSuccessBlock;

    if (offset > 0) {
        [self seek64:offset];
    }
    
    __weak SSHKitSFTPFile *weakSelf = self;
    
        [self.sftp.session dispatchAsyncOnSessionQueue:^{
            __strong SSHKitSFTPFile *strongSelf = weakSelf;
            
            NSError *error;
            NSDate *startTime = [NSDate date];
            
            [weakSelf asyncBeginReadChunk];
            [weakSelf asyncReadChunk:&error];
            
            NSDate *finishTime = [NSDate date];
            NSTimeInterval usedTime = [finishTime timeIntervalSinceDate:startTime];
            long long speed = strongSelf->_totalBytes / usedTime;
            NSString *formatedSpeed = [NSByteCountFormatter stringFromByteCount:speed countStyle:NSByteCountFormatterCountStyleDecimal];
            NSString *formatedFileSize = [NSByteCountFormatter stringFromByteCount:strongSelf->_totalBytes countStyle:NSByteCountFormatterCountStyleDecimal];
            NSLog(@"SSHKitCore download succ: size %@, time(sec) %f, speed %@", formatedFileSize, usedTime, formatedSpeed);
        }];
}

- (void)cancelAsyncReadFile {
    self.stage = SSHKitFileStageNone;
}

- (int)asyncRead:(int)asyncRequest buffer:(char *)buffer errorPtr:(NSError **)errorPtr {
    // [self dispatchSyncOnSessionQueue:
    // `sftp_async_read
    __block int result = -1;
    __weak SSHKitSFTPFile *weakSelf = self;
    __block NSError *error;

    [self.sftp.session dispatchSyncOnSessionQueue:^{
        error = [weakSelf returnErrorIfNotConnected];
        if (error) {
            return_from_block;
        }

        result = sftp_async_read(weakSelf.rawFile, buffer, MAX_XFER_BUF_SIZE, asyncRequest);
    }];
    
    if (result < 0 && result != -2) {
        if (errorPtr) {
            if (error) {
                *errorPtr = error;
            } else {
                *errorPtr = self.sftp.libsshSFTPError;
            }
        }
    }
    
    return result;
}

-(long)write:(const void *)buffer size:(long)size errorPtr:(NSError **)errorPtr {
    long totoalWriteLength = 0;
    NSError *error;
    long writeLength = [self sftpWrite:buffer size:size errorPtr:&error];
    totoalWriteLength += writeLength;
    
    if (writeLength < 0) {
        if (errorPtr) {
            *errorPtr = error;
        }
        return totoalWriteLength;
    }
    
    // TODO check window size?
    while (writeLength >= 0 && totoalWriteLength < size) {
        writeLength = [self sftpWrite:buffer size:size errorPtr:&error];
        
        if (writeLength < 0) {
            *errorPtr = error;
            return totoalWriteLength;
        }
        
        totoalWriteLength += writeLength;
    }
    
    return totoalWriteLength;
}

#pragma mark - file information

- (void)populateValuesFromSFTPAttributes:(sftp_attributes)fileAttributes parentPath:(NSString *)parentPath {
    if (parentPath != nil) {
        NSString *filename = [NSString stringWithUTF8String:fileAttributes->name];
        self.filename = filename;
        self.fullFilename = [parentPath stringByAppendingPathComponent:filename];
    }
    self.modificationDate = [NSDate dateWithTimeIntervalSince1970:fileAttributes->mtime];
    self.creationDate = [NSDate dateWithTimeIntervalSince1970:fileAttributes->createtime];
    self.lastAccess = [NSDate dateWithTimeIntervalSinceNow:fileAttributes->atime];
    self.fileSize = @(fileAttributes->size);
    self.ownerUserID = fileAttributes->uid;
    self.ownerGroupID = fileAttributes->gid;
    if (fileAttributes->owner) {
        self.ownerUserName = [[NSString alloc]initWithUTF8String:fileAttributes->owner];
    }
    if (fileAttributes->group) {
        self.ownerGroupName = [[NSString alloc]initWithUTF8String:fileAttributes->group];
    }
    self.posixPermissions = fileAttributes->permissions;
    self->_fileTypeLetter = [self fileTypeLetter:fileAttributes->permissions];
    self.isDirectory = S_ISDIR(fileAttributes->permissions);
#ifdef S_ISLNK
    self.isLink = S_ISLNK(fileAttributes->permissions);
#endif
    self.flags = fileAttributes->flags;
}

- (NSString *)kindOfFile {
    NSString *kind = @"";
    if (self.isDirectory) {
        kind = @"Folder";
    }
    
    if (!self.filename) {
        return kind;
    }
    
    NSString *extension = [self.filename pathExtension];
    CFStringRef typeForExt = UTTypeCreatePreferredIdentifierForTag(kUTTagClassFilenameExtension,(__bridge CFStringRef)extension , NULL);
    if (typeForExt) {
        
        NSString *typeDescription = (__bridge_transfer NSString *)UTTypeCopyDescription(typeForExt);
        if (typeDescription)
            kind = typeDescription;
    }
    
    return kind;
}

- (void)close {
    if (!self.sftp.session.isConnected) {
        // if not connected, ignore it.
        return;
    }
    __weak SSHKitSFTPFile *weakSelf = self;
    [self.sftp.session dispatchAsyncOnSessionQueue:^{
        __strong SSHKitSFTPFile *strongSelf = weakSelf;
        if (strongSelf.rawDirectory) {
            sftp_closedir(strongSelf.rawDirectory);
            strongSelf->_rawDirectory = nil;
        }
    }];
    [self.sftp.session dispatchAsyncOnSessionQueue:^{
        __strong SSHKitSFTPFile *strongSelf = weakSelf;
        if (strongSelf.rawFile) {
            sftp_close(strongSelf.rawFile);
            strongSelf->_rawFile = nil;
        }
    }];
    if (self.sftp) {
        [self.sftp.remoteFiles removeObject:self];
    }
}

- (SSHKitSFTPIsFileExist)isExist {
    SSHKitSFTPIsFileExist exist = SSHKitSFTPIsFileExistNo;
    NSError *error = [self updateStat];
    if (error && (error.code == SSHKitSFTPErrorCodeNoSuchFile || error.code == SSHKitSFTPErrorCodeEOF)) {
        return NO;
    }
    exist = SSHKitSFTPIsFileExistFile;
    if (self.isDirectory) {
        exist = SSHKitSFTPIsFileExistDirectory;
    }
    [self close];
    return exist;
}

#pragma mark - list dir

- (BOOL)directoryEof {
    return sftp_dir_eof(self.rawDirectory);
}

- (SSHKitSFTPFile *)readDirectory {
    __block sftp_attributes attributes = nil;
    __weak SSHKitSFTPFile *weakSelf = self;
    __block NSError *error;
    
    [self.sftp.session dispatchSyncOnSessionQueue:^{
        error = [weakSelf returnErrorIfNotConnected];
        if (error) {
            return_from_block;
        }
        attributes = sftp_readdir(weakSelf.sftp.rawSFTPSession, weakSelf.rawDirectory);
    }];
    
    if (!attributes) {
        return nil;
    }
    
    SSHKitSFTPFile *instance = [[SSHKitSFTPFile alloc] initWithSFTPAttributes: attributes parentPath:self.fullFilename];
    [SSHKitSFTPChannel freeSFTPAttributes:attributes];
    
    return instance;
}

- (NSArray *)listDirectory:(SSHKitSFTPListDirFilter)filter {
    // add call back to cancel it?
    NSMutableArray *files = [@[] mutableCopy];
    SSHKitSFTPFile *file = [self readDirectory];
    while (file != nil) {
        SSHKitSFTPListDirFilterCode code = SSHKitSFTPListDirFilterCodeAdd;
        if (filter) {
            code = filter(file);
        }
        switch (code) {
            case SSHKitSFTPListDirFilterCodeAdd:
                [files addObject:file];
                break;
            case SSHKitSFTPListDirFilterCodeCancel:
                return files;
                break;
            case SSHKitSFTPListDirFilterCodeIgnore:
                break;
            default:
                break;
        }
        file = [self readDirectory];
    }
    return files;
}

#pragma mark - Permissions conversion methods

/**
 Convert a mode field into "ls -l" type perms field. By courtesy of Jonathan Leffler
 http://stackoverflow.com/questions/10323060/printing-file-permissions-like-ls-l-using-stat2-in-c
 
 @param mode The numeric mode that is returned by the 'stat' function
 @return A string containing the symbolic representation of the file permissions.
 */
- (NSString *)convertPermissionToSymbolicNotation:(unsigned long)mode {
    static char *rwx[] = {"---", "--x", "-w-", "-wx", "r--", "r-x", "rw-", "rwx"};
    char bits[11];
    
    bits[0] = [self fileTypeLetter:mode];
    strcpy(&bits[1], rwx[(mode >> 6)& 7]);
    strcpy(&bits[4], rwx[(mode >> 3)& 7]);
    strcpy(&bits[7], rwx[(mode & 7)]);
    
    if (mode & S_ISUID) {
        bits[3] = (mode & 0100) ? 's' : 'S';
    }
    
    if (mode & S_ISGID) {
        bits[6] = (mode & 0010) ? 's' : 'l';
    }
    
    if (mode & S_ISVTX) {
        bits[9] = (mode & 0100) ? 't' : 'T';
    }
    
    bits[10] = '\0';
    
    return [NSString stringWithCString:bits encoding:NSUTF8StringEncoding];
}

/**
 Extracts the unix letter for the file type of the given permission value.
 
 @param mode The numeric mode that is returned by the 'stat' function
 @return A character that represents the given file type.
 */
- (char)fileTypeLetter:(unsigned long)mode {
    char c;
    
    if (S_ISREG(mode)) {
        c = '-';
    }
    else if (S_ISDIR(mode)) {
        c = 'd';
    }
    else if (S_ISBLK(mode)) {
        c = 'b';
    }
    else if (S_ISCHR(mode)) {
        c = 'c';
    }
#ifdef S_ISFIFO
    else if (S_ISFIFO(mode)) {
        c = 'p';
    }
#endif
#ifdef S_ISLNK
    else if (S_ISLNK(mode)) {
        c = 'l';
    }
#endif
#ifdef S_ISSOCK
    else if (S_ISSOCK(mode)) {
        c = 's';
    }
#endif
#ifdef S_ISDOOR
    // Solaris 2.6, etc.
    else if (S_ISDOOR(mode)) {
        c = 'D';
    }
#endif
    else {
        // Unknown type -- possibly a regular file?
        c = '?';
    }
    
    return c;
}

- (NSString *)description {
    return [NSString stringWithFormat:@"<%@: %p> Filename: %@", NSStringFromClass([self class]), self, self.filename];
}

- (NSComparisonResult)compare:(SSHKitSFTPFile *)otherFile {
    return [self.filename compare:otherFile.filename];
}

# pragma mark - property

- (void)setPosixPermissions:(unsigned long)posixPermissions {
    _posixPermissions = posixPermissions;
    self.permissions = [self convertPermissionToSymbolicNotation:posixPermissions];
}

- (void)setStage:(SSHKitFileStage)stage {
    if (!self.sftp) {
        _stage = stage;
        return;
    }
    if (_stage == stage) {
        return;
    }
    switch (stage) {
        case SSHKitFileStageReadingFile:
            [self.sftp.remoteFiles addObject:self];
            break;
        case SSHKitFileStageNone:
            [self.sftp.remoteFiles removeObject:self];
            break;
        default:
            break;
    }
    _stage = stage;
}

+ (NSError *)returnErrorIfNotConnected:(SSHKitSession *)session {
    if (session.isConnected) {
        return nil;
    }
    return [NSError errorWithDomain:SSHKitLibsshSFTPErrorDomain
                               code:SSHKitSFTPErrorCodeGenericFailure
                           userInfo: @{ NSLocalizedDescriptionKey : @"Session not connected" }];
}

- (NSError *)returnErrorIfNotConnected {
    return [SSHKitSFTPFile returnErrorIfNotConnected:self.sftp.session];
}

- (void)didReceiveData:(NSData *)data {
}


@end
