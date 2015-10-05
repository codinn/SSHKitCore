//
//  SSHKitSFTPRequest.h
//  SSHKitCore
//
//  Created by vicalloy on 9/11/15.
//
//

#import <Foundation/Foundation.h>
#import "SSHKitSFTPChannel.h"
#import "SSHKitCoreCommon.h"

@interface SSHKitSFTPRequest : NSObject
@property (nonatomic, readonly) SSHKitSFTPRequestStatusCode status;
@property (nonatomic, readonly, getter = isCancelled) BOOL cancelled;
@property (nonatomic, readonly, getter = isPaused) BOOL paused;
@property (nonatomic, weak) SSHKitSFTPChannel *sftpChannel;
@property (nonatomic, readwrite, copy) SSHKitSFTPRequestCancelHandler cancelHandler;
@property (nonatomic, strong) NSError *error;
@property (nonatomic, copy) id successBlock;
@property (nonatomic, copy) SSHKitSFTPClientFailureBlock failureBlock;

// may be called by the connection or the end user
- (void)cancel;
- (void)pause;

// Only the connection should call these methods
- (void)start:(SSHKitSFTPChannel *)sftpChannel; // subclasses must override
- (void)succeed; // subclasses must override and invoke their success blocks
- (void)fail; // subclasses need not override this

// Only subclasses should call these methods
- (BOOL)ready;
- (BOOL)checkSFTP;
- (BOOL)pathIsValid:(NSString *)path;
- (NSError *)errorWithCode:(SSHKitSFTPClientErrorCode)errorCode
          errorDescription:(NSString *)errorDescription
           underlyingError:(NSNumber *)underlyingError;
@end
