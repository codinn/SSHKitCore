//
//  SSHKitSFTPListFilesRequest.h
//  SSHKitCore
//
//  Created by vicalloy on 9/11/15.
//
//

#import "SSHKitSFTPRequest.h"
#import "SSHKitCoreCommon.h"

@interface SSHKitSFTPListFilesRequest : SSHKitSFTPRequest

- (id)initWithDirectoryPath:(NSString *)directoryPath
               successBlock:(SSHKitSFTPClientArraySuccessBlock)successBlock
               failureBlock:(SSHKitSFTPClientFailureBlock)failureBlock;

@end
