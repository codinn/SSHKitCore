//
//  SSHKitSFTPRequest.m
//  SSHKitCore
//
//  Created by vicalloy on 9/11/15.
//
//

#import "SSHKitSFTPRequest.h"

@interface SSHKitSFTPRequest ()

@property (nonatomic, readwrite, getter = isCancelled) BOOL cancelled;

@end

@implementation SSHKitSFTPRequest

- (void)cancel {
    if (self.cancelHandler) {
        SSHKitSFTPRequestCancelHandler handler = self.cancelHandler;
        dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), handler);
        self.cancelHandler = nil;
    }
    self.cancelled = YES;
}

- (void)start:(SSHKitSFTPSession *)sftpSession {
    self.sftpSession = sftpSession;
    [NSException raise:SSHKitSFTPRequestNotImplemented
                format:@"Request does not implement start"];
}

- (void)succeed {
    [NSException raise:SSHKitSFTPRequestNotImplemented
                format:@"Request does not implement finish"];
}

// potentially move these to the connection
- (BOOL)ready {
    if (self.isCancelled) {
        self.error = [self errorWithCode:SSHKitSFTPClientErrorCancelledByUser
                        errorDescription:@"Cancelled by user"
                         underlyingError:nil];
        return NO;
    }
    /*
    if ([self.sftpSession isConnected] == NO) {
        self.error = [self errorWithCode:SSHKitSFTPClientErrorNotConnected
                        errorDescription:@"Socket not connected"
                         underlyingError:nil];
        return NO;
    }
    */
    return YES;
}

- (BOOL)checkSFTP {
    // TODO check session
    return YES;
}

- (BOOL)pathIsValid:(NSString *)path {
    if ([path length] == 0) {
        self.error = [self errorWithCode:SSHKitSFTPClientErrorInvalidPath
                        errorDescription:@"Invalid path"
                         underlyingError:nil];
        return NO;
    }
    return YES;
}


- (NSError *)errorWithCode:(SSHKitSFTPClientErrorCode)errorCode
          errorDescription:(NSString *)errorDescription
           underlyingError:(NSNumber *)underlyingError {
    NSError *error = nil;
    if (underlyingError == nil) {
        error = [NSError errorWithDomain:SSHKitSFTPErrorDomain
                                    code:errorCode
                                userInfo:@{ NSLocalizedDescriptionKey : errorDescription }
                 ];
    } else {
        error = [NSError errorWithDomain:SSHKitSFTPErrorDomain
                                    code:errorCode
                                userInfo:@{ NSLocalizedDescriptionKey : errorDescription, SSHKitSFTPUnderlyingErrorKey : underlyingError }
                 ];
    }
    return error;
}

- (void)fail {
    SSHKitSFTPClientFailureBlock failureBlock = self.failureBlock;
    NSError *error = self.error;
    if (failureBlock) {
        dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
            failureBlock(error);
        });
    }
    self.successBlock = nil;
    self.failureBlock = nil;
}

@end
