//
//  SSHKitSFTP.m
//  SSHKitCore
//
//  Created by vicalloy on 8/26/15.
//
//

#import "SSHKitSFTP.h"
#import "SSHKitCore+Protected.h"

@implementation SSHKitSFTP

+ (void)freeSFTPAttributes:(sshkit_sftp_attributes)attributes {
    sftp_attributes_free(attributes);
}

- (instancetype)initWithDelegate:(id<SSHKitSFTPDelegate>)delegate {
    if (self = [super init]) {
        self->_delegate = delegate;
    }
    return self;
}

- (BOOL)initSFTP:(SSHKitSession *)session {
    self->_rawSFTPSession = sftp_new(session.rawSession);
    if (self.rawSFTPSession == NULL) {
        return NO;
    }
    int rc = sftp_init(self.rawSFTPSession);
    if (rc != SSH_OK) {
        // fprintf(stderr, "Error initializing SFTP session: %s.\n", sftp_get_error(sftp));
        sftp_free(self.rawSFTPSession);
        self->_rawSFTPSession = NULL;
        // return rc;
        return NO;
    }
    return YES;
}

- (void)close {
    sftp_free(self.rawSFTPSession);
    self->_rawSFTPSession = NULL;
}

- (SSHKitSFTPDirectory *)openDirectory:(NSString *)path {
    SSHKitSFTPDirectory* directory = [[SSHKitSFTPDirectory alloc]init:self path:path];
    return directory;
}

@end
