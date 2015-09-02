//
//  SSHKitSFTPDirectory.m
//  SSHKitCore
//
//  Created by vicalloy on 8/28/15.
//
//

#import "SSHKitSFTPDirectory.h"
#import "SSHKitCore+Protected.h"

@implementation SSHKitSFTPDirectory

- (instancetype)init:(SSHKitSFTP *)sftp path:(NSString *)path {
    if ((self = [super init])) {
        self->_sftp = sftp;
        self->_rawDirectory = sftp_opendir(sftp.rawSFTPSession, [path UTF8String]);
        if (self.rawDirectory == NULL) {
            // fprintf(stderr, "Error allocating SFTP session: %s\n", ssh_get_error(session));
            // return SSH_ERROR;
            return nil;
        }
    }
    return self;
}

- (NSInteger)closeDirectory {
    return sftp_closedir(self.rawDirectory);
}

- (BOOL)directoryEof {
    return sftp_dir_eof(self.rawDirectory);
}

- (sshkit_sftp_attributes)readDirectory {
    return sftp_readdir(self.sftp.rawSFTPSession, self.rawDirectory);
}

@end
