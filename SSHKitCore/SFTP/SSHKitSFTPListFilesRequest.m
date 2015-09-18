//
//  SSHKitSFTPListFilesRequest.m
//  SSHKitCore
//
//  Created by vicalloy on 9/11/15.
//
//

#import "SSHKitSFTPListFilesRequest.h"
#import "SSHKitSFTPFile.h"

@interface SSHKitSFTPListFilesRequest()

@property (nonatomic, copy) NSString *directoryPath;
@property (nonatomic, copy) NSArray *files;
@end

@implementation SSHKitSFTPListFilesRequest

// the request shouldn't be initialized with a connection
- (id)initWithDirectoryPath:(NSString *)directoryPath
               successBlock:(SSHKitSFTPClientArraySuccessBlock)successBlock
               failureBlock:(SSHKitSFTPClientFailureBlock)failureBlock {
    self = [super init];
    if (self) {
        self.successBlock = successBlock;
        self.failureBlock = failureBlock;
        self.directoryPath = directoryPath;
    }
    return self;
}

- (void)start {
    if ([self pathIsValid:self.directoryPath] == NO
        || [self ready] == NO
        || [self checkSFTP] == NO) {
        // [self.connection requestDidFail:self withError:self.error];
        return;
    }
    SSHKitSFTPFile *currentDirectory = [self.sftpChannel openDirectory:self.directoryPath];

    if ([self ready] == NO) {
        // [self.connection requestDidFail:self withError:self.error];
        return;
    }

    if (currentDirectory == nil) {
        // unable to open directory
        /*
        unsigned long lastError = libssh2_sftp_last_error(sftp);
        NSString *errorDescription = [NSString stringWithFormat:@"Unable to open directory: sftp error: %ld", lastError];

        // unable to initialize session
        self.error = [self errorWithCode:eSFTPClientErrorUnableToOpenDirectory
                        errorDescription:errorDescription
                         underlyingError:@(lastError)];
        [self.connection requestDidFail:self withError:self.error];
        */
        return;
    }

    NSMutableArray *files = [[NSMutableArray alloc] init];
    // TODO cancel & fail
    SSHKitSFTPFile *subFile = [currentDirectory readDirectory];
    while (subFile != nil) {
        [files addObject:subFile];
        subFile = [currentDirectory readDirectory];
    }
    [currentDirectory closeDirectory];
    /*
    do {
        memset(buffer, 0, sizeof(buffer));
        while (   ((result = libssh2_sftp_readdir(handle, buffer, cBufferSize, &attributes)) == LIBSSH2SFTP_EAGAIN)
               && self.isCancelled == NO){
            waitsocket(socketFD, session);
        }
        if ([self ready] == NO) {
            [self.connection requestDidFail:self withError:self.error];
            return;
        }
        if (result > 0) {
            NSString *filename = [[NSString alloc] initWithBytes:buffer
                                                          length:result
                                                        encoding:NSUTF8StringEncoding];
            // skip . and ..
            if ([filename isEqualToString:@"."] || [filename isEqualToString:@".."]) {
                continue;
            }
            NSString *filepath = [self.directoryPath stringByAppendingPathComponent:filename];
            NSDictionary *attributesDictionary = [NSDictionary dictionaryWithAttributes:attributes];
            DLSFTPFile *file = [[DLSFTPFile alloc] initWithPath:filepath
                                                     attributes:attributesDictionary];
            [files addObject:file];
        }
    } while (result > 0);
    */

    /*
    if (result < 0) {
        result = libssh2_sftp_last_error(sftp);
        while (   ((libssh2_sftp_closedir(handle)) == LIBSSH2SFTP_EAGAIN)
               && self.isCancelled == NO) {
            waitsocket(socketFD, session);
        }
        // error reading
        NSString *errorDescription = [NSString stringWithFormat:@"Read directory failed with code %ld", result];
        self.error = [self errorWithCode:eSFTPClientErrorUnableToReadDirectory
                        errorDescription:errorDescription
                         underlyingError:@(result)];
        [self.connection requestDidFail:self withError:self.error];
        return;
    }

    // close the handle
    while((   (result = libssh2_sftp_closedir(handle)) == LIBSSH2SFTP_EAGAIN)
          && self.isCancelled == NO){
        waitsocket(socketFD, session);
    }
    if (result) {
        NSString *errorDescription = [NSString stringWithFormat:@"Close directory handle failed with code %ld", result];
        self.error = [self errorWithCode:eSFTPClientErrorUnableToCloseDirectory
                        errorDescription:errorDescription
                         underlyingError:@(result)];
        [self.connection requestDidFail:self withError:self.error];
        return;
    }
    */

    [files sortUsingSelector:@selector(compare:)];
    self.files = files;
    // [self.connection requestDidComplete:self];
}

- (void)succeed {
    SSHKitSFTPClientArraySuccessBlock successBlock = self.successBlock;
    NSArray *files = self.files;
    if (successBlock) {
        dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
            successBlock(files);
        });
    }
    self.successBlock = nil;
    self.failureBlock = nil;
}

@end
