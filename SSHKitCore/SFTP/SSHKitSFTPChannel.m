//
//  SSHKitSFTP.m
//  SSHKitCore
//
//  Created by vicalloy on 8/26/15.
//
//

#import "SSHKitCore+Protected.h"
#import "SSHKitChannel.h"

typedef NS_ENUM(NSUInteger, SessionChannelReqState) {
    SessionChannelReqNone = 0,  // session channel has not been opened yet
    SessionChannelReqSFTP,       // is requesting a sftp
};

@interface SSHKitSFTPChannel()

@property (nonatomic) SessionChannelReqState   reqState;

@end

@implementation SSHKitSFTPChannel

@synthesize rawSFTPSession;

- (instancetype)initWithSession:(SSHKitSession *)session delegate:(id<SSHKitChannelDelegate>)aDelegate {
    if (self = [super initWithSession:session delegate:aDelegate]) {
        _reqState = SessionChannelReqNone;
    }
    
    return self;
}

- (int)_didReceiveData:(NSData *)readData isSTDError:(int)isSTDError {
    if (!self.isOpen) {
        return 0;
    }
    if (isSTDError) {
    } else {
        for (SSHKitSFTPFile *file in _remoteFiles) {
            [file didReceiveData:readData];
        }
    }
    // pass data to ssh_channel_read
    return 0;
}

- (void)doOpen {
    switch (self.reqState) {
        case SessionChannelReqNone:
            // 1. open session channel
            [self _openSession];
            break;
        case SessionChannelReqSFTP:
            // 2. request sftp
            [self _requestSFTP];
            break;
    }
}

- (void)_openSession {
    int result = ssh_channel_open_session(self.rawChannel);
    
    switch (result) {
        case SSH_AGAIN:
            // try next time
            break;;
            
        case SSH_OK:
            // succeed, requests a pty
            self.reqState = SessionChannelReqSFTP;
            [self _requestSFTP];
            break;
            
        default:
            // open failed
            [self doCloseWithError:self.session.libsshError];
            [self.session disconnectIfNeeded];
            break;
    }
}

- (void)_requestSFTP {
    int result = ssh_channel_request_sftp(self.rawChannel);
    
    switch (result) {
        case SSH_AGAIN: // try again
            break;
            
        case SSH_OK:
            if ([self _sftpInit]) {
                self.reqState = SessionChannelReqNone;
            		self.stage = SSHKitChannelStageReady;
								// TODO
                // [self _registerCallbacks];
                // opened
                if (_delegateFlags.didOpen) {
                    [self.delegate channelDidOpen:self];
                }
                // NSLog(@"sftp session opened");
            } else {
            		[self doCloseWithError:self.session.libsshError];
                [self.session disconnectIfNeeded];
            }
            break;
        default:
            // open failed
            [self doCloseWithError:self.session.libsshError];
            [self.session disconnectIfNeeded];
            break;
    }
}

- (BOOL)_sftpInit {
    self.rawSFTPSession = sftp_new_channel(self.session.rawSession, self.rawChannel);
    if (self.rawSFTPSession == NULL) {
        // NSLog(@(ssh_get_error(session.rawSession)));
        return NO;
    }
    int rc = sftp_init(self.rawSFTPSession);
    if (rc != SSH_OK) {
        // fprintf(stderr, "Error initializing SFTP session: %s.\n", sftp_get_error(sftp));
        sftp_free(self.rawSFTPSession);
        self.rawSFTPSession = NULL;
        // return rc;
        return NO;
    }
    return YES;
}

#pragma mark - SFTP API

+ (void)freeSFTPAttributes:(sshkit_sftp_attributes)attributes {
    sftp_attributes_free(attributes);
}

- (BOOL)isFileExist:(NSString *)path {
    SSHKitSFTPFile* file = [[SSHKitSFTPFile alloc]init:self path:path isDirectory:NO];
    // TODO handle error
    __block BOOL isExist;
    [self.session dispatchSyncOnSessionQueue:^{
        isExist = [file isExist];
    }];
    return isExist;
}

- (SSHKitSFTPFile *)getDirectory:(NSString *)path {
    return [[SSHKitSFTPFile alloc]init:self path:path isDirectory:YES];
}

- (SSHKitSFTPFile *)openDirectory:(NSString *)path errorPtr:(NSError **)errorPtr {
    SSHKitSFTPFile* directory = [self getDirectory:path];

    [self.session dispatchSyncOnSessionQueue:^{
        NSError *error = [directory open];
        if (errorPtr) {
            *errorPtr = error;
        }
    }];

    if (*errorPtr) {
        return nil;
    }

    return directory;
}

- (SSHKitSFTPFile *)getFile:(NSString *)path {
    return [[SSHKitSFTPFile alloc]init:self path:path isDirectory:NO];
}

- (SSHKitSFTPFile *)openFile:(NSString *)path errorPtr:(NSError **)errorPtr {
    SSHKitSFTPFile* file = [self getFile:path];

    [self.session dispatchSyncOnSessionQueue:^{
        NSError *error = [file open];
        if (errorPtr) {
            *errorPtr = error;
        }
    }];

    if (*errorPtr) {
        return nil;
    }

    return file;
}

- (SSHKitSFTPFile *)openFile:(NSString *)path accessType:(int)accessType mode:(unsigned long)mode errorPtr:(NSError **)errorPtr {
    SSHKitSFTPFile* file = [self getFile:path];

    [self.session dispatchSyncOnSessionQueue:^{
        NSError *error = [file openFile:accessType mode:mode];
        if (errorPtr) {
            *errorPtr = error;
        }
    }];

    if (*errorPtr) {
        return nil;
    }

    return file;
}

- (SSHKitSFTPFile *)openFileForWrite:(NSString *)path shouldResume:(BOOL)shouldResume mode:(unsigned long)mode errorPtr:(NSError **)errorPtr {
    SSHKitSFTPFile* file = [self getFile:path];

    [self.session dispatchSyncOnSessionQueue:^{
        NSError *error = [file openFileForWrite:shouldResume mode:mode];
        if (errorPtr) {
            *errorPtr = error;
        }
    }];

    if (*errorPtr) {
        return nil;
    }

    return file;
}

- (NSString *)canonicalizePath:(NSString *)path {
    __block NSString *newPath;
    __weak SSHKitSFTPChannel *weakSelf = self;
    [self.session dispatchSyncOnSessionQueue:^{
        newPath = [NSString stringWithUTF8String:sftp_canonicalize_path(weakSelf.rawSFTPSession, [path UTF8String])];
    }];
    return newPath;
}

- (int)rename:(NSString *)original newName:(NSString *)newName {
    __block int returnCode;
    __weak SSHKitSFTPChannel *weakSelf = self;
    [self.session dispatchSyncOnSessionQueue:^{
        returnCode = sftp_rename(weakSelf.rawSFTPSession, [original UTF8String], [newName UTF8String]);
    }];
    return returnCode;
}

- (int)chmod:(NSString *)filePath mode:(unsigned long)mode {
    __block int returnCode;
    __weak SSHKitSFTPChannel *weakSelf = self;
    [self.session dispatchSyncOnSessionQueue:^{
        returnCode = sftp_chmod(weakSelf.rawSFTPSession, [filePath UTF8String], mode);
    }];
    return returnCode;
}

- (int)mkdir:(NSString *)directoryPath mode:(unsigned long)mode {
    __block int returnCode;
    __weak SSHKitSFTPChannel *weakSelf = self;
    [self.session dispatchSyncOnSessionQueue:^{
        returnCode = sftp_mkdir(weakSelf.rawSFTPSession, [directoryPath UTF8String], mode);
    }];
    return returnCode;
}

- (int)rmdir:(NSString *)directoryPath {
    __block int returnCode;
    __weak SSHKitSFTPChannel *weakSelf = self;
    [self.session dispatchSyncOnSessionQueue:^{
        returnCode = sftp_rmdir(weakSelf.rawSFTPSession, [directoryPath UTF8String]);
    }];
    return returnCode;
}

- (int)unlink:(NSString *)filePath {
    __block int returnCode;
    __weak SSHKitSFTPChannel *weakSelf = self;
    [self.session dispatchSyncOnSessionQueue:^{
        returnCode = sftp_unlink(weakSelf.rawSFTPSession, [filePath UTF8String]);
    }];
    return returnCode;
}

#pragma mark - property

- (NSMutableArray *)remoteFiles {
    if (_remoteFiles == nil) {
        _remoteFiles = [@[]mutableCopy];
    }
    return _remoteFiles;
}

#pragma mark Diagnostics

- (int)getLastSFTPError {
    __block int errorCode;
    __weak SSHKitSFTPChannel *weakSelf = self;
    [self.session dispatchSyncOnSessionQueue:^{
        errorCode = sftp_get_error(weakSelf.rawSFTPSession);
    }];
    return errorCode;
}

- (NSError *)libsshSFTPError {
    if(!self.session.rawSession) {
        return nil;
    }
    
    __block NSError *error;
    __weak SSHKitSFTPChannel *weakSelf = self;
    
    int code = [self getLastSFTPError];
    [self.session dispatchSyncOnSessionQueue :^{ @autoreleasepool {
        
        if (code == SSHKitErrorNoError) {
            return_from_block;
        }
        
        const char* errorStr = ssh_get_error(weakSelf.session.rawSession);
        
        error = [NSError errorWithDomain:SSHKitLibsshSFTPErrorDomain
                                    code:code
                                userInfo: errorStr ? @{ NSLocalizedDescriptionKey : @(errorStr) } : nil];
    }}];
    
    return error;
}

@end
