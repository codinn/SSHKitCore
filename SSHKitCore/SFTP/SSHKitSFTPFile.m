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

typedef NS_ENUM(NSInteger, SSHKitFileStage)  {
    SSHKitFileStageNone = 0,
    SSHKitFileStageReadingFile,
};

@interface SSHKitSFTPFile () {
    dispatch_group_t _readChunkGroup;
    unsigned long long _totalBytes;
    int _asyncRequest;
    dispatch_queue_t _readChunkQueue;
    int _readedpackageLen;
    int _againCount;
}

@property (nonatomic, readwrite) BOOL isDirectory;
@property (nonatomic, strong) NSDate *creationDate;
@property (nonatomic, strong) NSDate *modificationDate;
@property (nonatomic, strong) NSDate *lastAccess;
@property (nonatomic, strong) NSNumber *fileSize;
@property (nonatomic, readwrite) unsigned long ownerUserID;
@property (nonatomic, readwrite) unsigned long ownerGroupID;
@property (nonatomic, strong) NSString *permissions;
@property (nonatomic, readwrite) u_long flags;

@property (nonatomic) SSHKitFileStage stage;
@property (nonatomic, copy) SSHKitSFTPClientReadFileBlock readFileBlock;
@property (nonatomic, copy) SSHKitSFTPClientProgressBlock progressBlock;
@property (nonatomic, copy) SSHKitSFTPClientFileTransferSuccessBlock fileTransferSuccessBlock;
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
    // TODO use sftp_stat to get file info.
    return self;
}

- (void)openDirectory {
    self->_rawDirectory = sftp_opendir(self.sftp.rawSFTPSession, [self.fullFilename UTF8String]);
    if (self.rawDirectory == NULL) {
        // fprintf(stderr, "Error allocating SFTP session: %s\n", ssh_get_error(session));
        // return SSH_ERROR;
    }
}

- (BOOL)updateStat {
    sftp_attributes file_attributes = sftp_stat(self.sftp.rawSFTPSession, [self.fullFilename UTF8String]);
    if (file_attributes == NULL) {
        return NO;
    }
    [self populateValuesFromSFTPAttributes:file_attributes parentPath:nil];
    [SSHKitSFTPChannel freeSFTPAttributes:file_attributes];
    return YES;
}

- (void)open {
    if (self.isDirectory) {
        [self openDirectory];
    } else {
        [self openFile];
    }
    // if updateStat not exec
    if (self.permissions == nil) {
        [self updateStat];
    }
}

- (void)openFile {
    [self openFile:O_RDONLY mode:0];
}

- (void)openFileForWrite:(BOOL)shouldResume mode:(unsigned long)mode {
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
    [self openFile:oflag mode:mode];
    if (self.permissions == nil) {
        [self updateStat];
    }
}

- (void)openFile:(int)accessType mode:(unsigned long)mode {
    // TODO create file
    // http://api.libssh.org/master/group__libssh__sftp.html#gab95cb5fe091efcc49dfa7729e4d48010
    _rawFile = sftp_open(self.sftp.rawSFTPSession, [self.fullFilename UTF8String], accessType, mode);
    if (_rawFile == NULL) {
        return;
    }
    sftp_file_set_nonblocking(self.rawFile);
}

- (void)asyncReadFile:(unsigned long long)offset
        readFileBlock:(SSHKitSFTPClientReadFileBlock)readFileBlock
        progressBlock:(SSHKitSFTPClientProgressBlock)progressBlock
        fileTransferSuccessBlock:(SSHKitSFTPClientFileTransferSuccessBlock)fileTransferSuccessBlock
        fileTransferFailBlock:(SSHKitSFTPClientFailureBlock)fileTransferFailBlock {
    _againCount = 0;
    _readedpackageLen = 0;
    _totalBytes = 0;
    self.readFileBlock = readFileBlock;
    self.progressBlock = progressBlock;
    self.fileTransferFailBlock = fileTransferFailBlock;
    self.fileTransferSuccessBlock = fileTransferSuccessBlock;
    if (offset > 0) {
        sftp_seek64(self.rawFile, offset);
    }
    _asyncRequest = sftp_async_read_begin(self.rawFile, MAX_XFER_BUF_SIZE);
    if (_asyncRequest) {
        self.stage = SSHKitFileStageReadingFile;
    }
}

- (void)cancelAsyncReadFile {
    self.stage = SSHKitFileStageNone;
}

- (int)_asyncRead:(int)asyncRequest buffer:(char *)buffer {
    // [self dispatchAsyncOnSessionQueue:
    // `sftp_async_read
    int result = sftp_async_read(_rawFile, buffer, MAX_XFER_BUF_SIZE, asyncRequest);
    if (result < 0 && result != -2) {
        // Received a too big DATA packet from sftp server: 751 and asked for 8
        printf("%s: %d\n", ssh_get_error(self.sftp.session.rawSession), result);
    }
    return result;
}

- (void)_asyncReadFile {
    // self.stage = SSHKitFileStageReadingFile;
    int nbytes;
    // char buffer[MAX_XFER_BUF_SIZE];  // how to free this array?
    char *buffer = malloc(sizeof(char) * MAX_XFER_BUF_SIZE);
    // long counter = 0L;
    nbytes = [self _asyncRead:_asyncRequest buffer:buffer];
    if (nbytes == SSHKit_SSH_AGAIN) {
        _againCount += 1;
        // NSLog(@"SSHKit_SSH_AGAIN");
        return;
    }
    _totalBytes += nbytes;
    // NSLog(@"AGAIN: %d;  _asyncRequest: %d; len: %d; total: %llu", _againCount, _asyncRequest, nbytes, _totalBytes);
    _againCount = 0;
    if (nbytes < 0) {
        // finish or fail
        self.stage = SSHKitFileStageNone;
        NSError *error = nil;  // TODO
        free(buffer);
        self.fileTransferFailBlock(error);
        return;
    }
    if (nbytes == 0) {
        // finish or fail
        self.stage = SSHKitFileStageNone;
        // SSHKitSFTPFile *file, NSDate *startTime, NSDate *finishTime)
        free(buffer);
        self.fileTransferSuccessBlock(self, nil, nil, nil);
        return;
    }
    _readFileBlock(buffer, nbytes);
    _progressBlock(nbytes, _totalBytes, self.fileSize.longLongValue);
    _readedpackageLen += nbytes;
    if (_readedpackageLen < MAX_XFER_BUF_SIZE && _totalBytes < self.fileSize.longLongValue) {  // if not all data readed
        // NSLog(@"not all data readed.");
        return;
    }
    _readedpackageLen = 0;
    // free(buffer);
    _asyncRequest = sftp_async_read_begin(self.rawFile, MAX_XFER_BUF_SIZE);
    if (_asyncRequest == 0) {
        // finish or fail
        self.stage = SSHKitFileStageNone;
        self.fileTransferSuccessBlock(self, nil, nil, nil);
        return;
    }
    if (_asyncRequest < 0) {
        // finish or fail
        self.stage = SSHKitFileStageNone;
        NSError *error = nil;  // TODO
        self.fileTransferFailBlock(error);
        return;
    }
}

-(long)write:(const void *)buffer size:(long)size {
    long totoalWriteLength = 0;
    long writeLength = sftp_write(self.rawFile, buffer, size);
    totoalWriteLength += writeLength;
    // TODO check window size?
    while (writeLength >= 0 && totoalWriteLength < size) {
        writeLength = sftp_write(self.rawFile, buffer, size);
        totoalWriteLength += writeLength;
    }
    if (writeLength < 0) {  // get a error
        return writeLength;
    }
    return totoalWriteLength;
}

- (void)didReceiveData:(NSData *)data {
    // TODO call asyncRead on data arraived
    __weak SSHKitSFTPFile *weakSelf = self;
    if (self.stage == SSHKitFileStageReadingFile) {
        // 16397 - 16384
        [self.sftp.session dispatchAsyncOnSessionQueue:^{
            __strong SSHKitSFTPFile *strongSelf = weakSelf;
            [strongSelf _asyncReadFile];
        }];
    }
}


- (instancetype)initWithSFTPAttributes:(sftp_attributes)fileAttributes parentPath:(NSString *)parentPath {
    if ((self = [super init])) {
        [self populateValuesFromSFTPAttributes:fileAttributes parentPath:parentPath];
    }
    return self;
}

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
    self.posixPermissions = fileAttributes->permissions;
    self->_fileTypeLetter = [self fileTypeLetter:fileAttributes->permissions];
    self.isDirectory = S_ISDIR(fileAttributes->permissions);
    self.flags = fileAttributes->flags;
}

- (void)close {
    if (self.rawDirectory != nil) {
        sftp_closedir(self.rawDirectory);
    }
    if (self.rawFile != nil) {
        sftp_close(self.rawFile);
    }
    if (self.sftp) {
        [self.sftp.remoteFiles removeObject:self];
    }
}

- (BOOL)isExist {
    BOOL exist = YES;
    if ([self updateStat]) {
    } else if ([self.sftp getLastSFTPError] == SSH_FX_NO_SUCH_FILE) {
        exist = NO;
    } else {
        exist = NO;
    }
    [self close];
    return exist;
}

- (BOOL)directoryEof {
    return sftp_dir_eof(self.rawDirectory);
}

- (SSHKitSFTPFile *)readDirectory {
    sftp_attributes attributes = sftp_readdir(self.sftp.rawSFTPSession, self.rawDirectory);
    if (!attributes) {
        return nil;
    }
    SSHKitSFTPFile *instance = [[SSHKitSFTPFile alloc] initWithSFTPAttributes: attributes parentPath:self.fullFilename];
    [SSHKitSFTPChannel freeSFTPAttributes:attributes];
    return instance;
}

- (NSArray *)listDirectory {
    // add call back to cancel it?
    NSMutableArray *files = [@[] mutableCopy];
    SSHKitSFTPFile *file = [self readDirectory];
    while (file != nil) {
        // ignore self and parent
        if (![file.filename isEqualToString:@"."] && ![file.filename isEqualToString:@".."]) {
            [files addObject:file];
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

@end
