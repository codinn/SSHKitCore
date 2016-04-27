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

@property (nonatomic, readwrite) sftp_session rawSFTPSession;
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
            [file channel:self didReadStdoutData:readData];
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

- (int)getLastSFTPError {
    return sftp_get_error(self.rawSFTPSession);
}

- (BOOL)isFileExist:(NSString *)path {
    SSHKitSFTPFile* file = [[SSHKitSFTPFile alloc]init:self path:path isDirectory:NO];
    // TODO handle error
    return [file isExist];
}

- (SSHKitSFTPFile *)getDirectory:(NSString *)path {
    return [[SSHKitSFTPFile alloc]init:self path:path isDirectory:YES];
}

- (SSHKitSFTPFile *)openDirectory:(NSString *)path {
    SSHKitSFTPFile* directory = [self getDirectory:path];
    // TODO handle error
    [directory open];
    return directory;
}

- (SSHKitSFTPFile *)getFile:(NSString *)path {
    return [[SSHKitSFTPFile alloc]init:self path:path isDirectory:NO];
}

- (SSHKitSFTPFile *)openFile:(NSString *)path {
    SSHKitSFTPFile* file = [self getFile:path];
    // TODO handle error
    [file open];
    return file;
}

- (SSHKitSFTPFile *)openFile:(NSString *)path accessType:(int)accessType mode:(unsigned long)mode {
    SSHKitSFTPFile* file = [self getFile:path];
    // TODO handle error
    [file openFile:accessType mode:mode];
    return file;
}

- (SSHKitSFTPFile *)openFileForWrite:(NSString *)path shouldResume:(BOOL)shouldResume mode:(unsigned long)mode {
    SSHKitSFTPFile* file = [self getFile:path];
    // TODO handle error
    [file openFileForWrite:shouldResume mode:mode];
    return file;
}

- (NSString *)canonicalizePath:(NSString *)path {
    return [NSString stringWithUTF8String:sftp_canonicalize_path(self.rawSFTPSession, [path UTF8String])
            ];
}

- (int)rename:(NSString *)original mode:(NSString *)newName {
    return sftp_rename(self.rawSFTPSession, [original UTF8String], [newName UTF8String]);
}

- (int)chmod:(NSString *)filePath mode:(unsigned long)mode {
    return sftp_chmod(self.rawSFTPSession, [filePath UTF8String], mode);
}

- (int)mkdir:(NSString *)directoryPath mode:(unsigned long)mode {
    return sftp_mkdir(self.rawSFTPSession, [directoryPath UTF8String], mode);
}

- (NSMutableArray *)remoteFiles {
    if (_remoteFiles == nil) {
        _remoteFiles = [@[]mutableCopy];
    }
    return _remoteFiles;
}

- (int)rmdir:(NSString *)directoryPath {
    return sftp_rmdir(self.rawSFTPSession, [directoryPath UTF8String]);
}

- (int)unlink:(NSString *)filePath {
    return sftp_unlink(self.rawSFTPSession, [filePath UTF8String]);
}

@end
