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

- (void)doCloseWithError:(NSError *)error {
    // file will remove from remoteFiles in loop
    // close file and other function
    NSMutableArray *templateRemoteFiles = [self.remoteFiles copy];
    for (SSHKitSFTPFile *file in templateRemoteFiles) {
        [file doFileTransferFail:error];
    }
    
    // close channel
    [super doCloseWithError:error];
}

#pragma mark - SFTP API

+ (void)freeSFTPAttributes:(sshkit_sftp_attributes)attributes {
    sftp_attributes_free(attributes);
}

- (SSHKitSFTPIsFileExist)isFileExist:(NSString *)path {
    SSHKitSFTPFile* file = [[SSHKitSFTPFile alloc]init:self path:path isDirectory:NO];
    // TODO handle error
    __block SSHKitSFTPIsFileExist isExist;
    [self.session dispatchSyncOnSessionQueue:^{
        isExist = [file isExist];
    }];
    return isExist;
}

- (NSString *)canonicalizePath:(NSString *)path errorPtr:(NSError **)errorPtr {
    __block NSString *newPath = nil;
    __weak SSHKitSFTPChannel *weakSelf = self;
    [self.session dispatchSyncOnSessionQueue:^{
        char *charNewPath = sftp_canonicalize_path(weakSelf.rawSFTPSession, [path UTF8String]);
        if (charNewPath) {
            newPath = [NSString stringWithUTF8String:charNewPath];
        }
    }];
    if (!newPath && errorPtr) {
        *errorPtr = self.libsshSFTPError;
    }
    return newPath;
}

- (NSError *)rename:(NSString *)original newName:(NSString *)newName {
    __block int returnCode;
    __weak SSHKitSFTPChannel *weakSelf = self;
    [self.session dispatchSyncOnSessionQueue:^{
        returnCode = sftp_rename(weakSelf.rawSFTPSession, [original UTF8String], [newName UTF8String]);
    }];
    return [self libsshSFTPError:returnCode];
}

- (NSError *)chmod:(NSString *)filePath mode:(unsigned long)mode {
    __block int returnCode;
    __weak SSHKitSFTPChannel *weakSelf = self;
    [self.session dispatchSyncOnSessionQueue:^{
        returnCode = sftp_chmod(weakSelf.rawSFTPSession, [filePath UTF8String], mode);
    }];
    return [self libsshSFTPError:returnCode];
}

- (NSError *)mkdir:(NSString *)directoryPath mode:(unsigned long)mode {
    __block int returnCode;
    __weak SSHKitSFTPChannel *weakSelf = self;
    [self.session dispatchSyncOnSessionQueue:^{
        returnCode = sftp_mkdir(weakSelf.rawSFTPSession, [directoryPath UTF8String], mode);
    }];
    return [self libsshSFTPError:returnCode];
}

- (NSError *)rmdir:(NSString *)directoryPath {
    __block int returnCode;
    __weak SSHKitSFTPChannel *weakSelf = self;
    [self.session dispatchSyncOnSessionQueue:^{
        returnCode = sftp_rmdir(weakSelf.rawSFTPSession, [directoryPath UTF8String]);
    }];
    return [self libsshSFTPError:returnCode];
}

- (NSError *)unlink:(NSString *)filePath {
    __block int returnCode;
    __weak SSHKitSFTPChannel *weakSelf = self;
    [self.session dispatchSyncOnSessionQueue:^{
        returnCode = sftp_unlink(weakSelf.rawSFTPSession, [filePath UTF8String]);
    }];
    return [self libsshSFTPError:returnCode];
}

- (NSString *)readlink:(NSString *)path errorPtr:(NSError **)errorPtr {
    __block NSString *symlinkTarget = nil;
    __weak typeof(self) weakSelf = self;
    
    [self.session dispatchSyncOnSessionQueue:^{
        char * cSymlinkTarget = sftp_readlink(weakSelf.rawSFTPSession, [path UTF8String]);
        if (cSymlinkTarget == NULL) {
        } else {
            symlinkTarget = [[NSString alloc]initWithUTF8String:cSymlinkTarget];
        }
    }];
    
    if (symlinkTarget == nil && errorPtr) {
        NSError *error = self.libsshSFTPError;
        if (!error) {
            error = [NSError errorWithDomain:SSHKitLibsshSFTPErrorDomain
                                        code:SSHKitSFTPErrorCodeGenericFailure
                                    userInfo: @{ NSLocalizedDescriptionKey : @"Generic failure." }];
        }
        *errorPtr = error;
    }
    
    return symlinkTarget;
}

- (NSError *)symlink:(NSString *)targetPath destination:(NSString *)destination {
    __block int returnCode;
    __weak SSHKitSFTPChannel *weakSelf = self;
    
    [self.session dispatchSyncOnSessionQueue:^{
        returnCode = sftp_symlink(weakSelf.rawSFTPSession, [targetPath UTF8String], [destination UTF8String]);
    }];
    
    return [self libsshSFTPError:returnCode];
}

#pragma mark - property

- (NSMutableArray *)remoteFiles {
    if (_remoteFiles == nil) {
        _remoteFiles = [@[]mutableCopy];
    }
    return _remoteFiles;
}

#pragma mark Diagnostics

- (int)getSFTPErrorCode {
    __block int errorCode;
    __weak SSHKitSFTPChannel *weakSelf = self;

    [self.session dispatchSyncOnSessionQueue:^{
        errorCode = sftp_get_error(weakSelf.rawSFTPSession);
    }];

    return errorCode;
}

- (NSError *)libsshSFTPError:(int)errorCode {
    if (errorCode == 0) {
        return nil;
    }
    
    return self.libsshSFTPError;
}

- (NSError *)libsshSFTPError {
    int errorCode = [self getSFTPErrorCode];
    NSString *errorStr = nil;
    switch (errorCode) {
        case SSHKitSFTPErrorCodeOK:
            return nil;
            break;
            
        case SSHKitSFTPErrorCodeEOF:
            errorStr = @"End-of-file encountered.";
            break;
            
        case SSHKitSFTPErrorCodeNoSuchFile:
            errorStr = @"File doesn't exist.";
            break;
            
        case SSHKitSFTPErrorCodePermissionDenied:
            errorStr = @"Permission denied.";
            break;
            
        case SSHKitSFTPErrorCodeGenericFailure:
            errorStr = @"Generic failure.";
            break;
            
        case SSHKitSFTPErrorCodeBadMessage:
            errorStr = @"Garbage received from server.";
            break;
            
        case SSHKitSFTPErrorCodeNoConnection:
            errorStr = @"No connection has been set up.";
            break;
            
        case SSHKitSFTPErrorCodeConnectionLost:
            errorStr = @"There was a connection, but we lost it.";
            break;
            
        case SSHKitSFTPErrorCodeOpUnsupported:
            errorStr = @"Operation not supported by the server.";
            break;
            
        case SSHKitSFTPErrorCodeInvalidHandle:
            errorStr = @"Invalid file handle.";
            break;
            
        case SSHKitSFTPErrorCodeNoSuchPath:
            errorStr = @"No such file or directory path exists.";
            break;
            
        case SSHKitSFTPErrorCodeFileAlreadyExists:
            errorStr = @"An attempt to create an already existing file or directory has been made.";
            break;
            
        case SSHKitSFTPErrorCodeWriteProtect:
            errorStr = @"We are trying to write on a write-protected filesystem.";
            break;
            
        case SSHKitSFTPErrorCodeNoMedia:
            errorStr = @"No media in remote drive.";
            break;
            
            
        default:
            break;
    }
    
    NSError *error = [NSError errorWithDomain:SSHKitLibsshSFTPErrorDomain
                                code:errorCode
                            userInfo: errorStr ? @{ NSLocalizedDescriptionKey : errorStr } : nil];
    return error;
    // return [self libsshSFTPError:code];
}

@end
