//
//  SSHKitSFTPDirectory.h
//  SSHKitCore
//
//  Created by vicalloy on 8/28/15.
//
//

#import <Foundation/Foundation.h>
#import "SSHKitCoreCommon.h"

@class SSHKitSFTP;

@interface SSHKitSFTPDirectory : NSObject

@property (nonatomic, readonly) SSHKitSFTP *sftp;
@property (nonatomic, readonly) BOOL directoryEof;
- (instancetype)init:(SSHKitSFTP *)sftp path:(NSString *)path;
- (NSInteger)closeDirectory;
- (sshkit_sftp_attributes)readDirectory;
// TODO read

@end
