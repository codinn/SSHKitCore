//
//  SSHKitSFTP.m
//  SSHKitCore
//
//  Created by vicalloy on 8/26/15.
//
//

#import "SSHKitCore+Protected.h"
#import "SSHKitChannel.h"

@implementation SSHKitSFTPChannel

+ (void)freeSFTPAttributes:(sshkit_sftp_attributes)attributes {
    sftp_attributes_free(attributes);
}

- (instancetype)initWithChannel:(SSHKitChannel *)channel delegate:(id<SSHKitChannelDelegate>)delegate {
    if (self = [super init]) {
        _delegate = delegate;
        _sshSession = channel.session;
        _sshChannel = channel;
        channel.delegate = self;
        if (channel.stage == SSHKitChannelStageReadWrite) {
            [self channelDidOpen:channel];
        }
    }
    return self;
}

- (instancetype)initWithSession:(SSHKitSession *)session delegate:(id<SSHKitChannelDelegate>)delegate {
    SSHKitChannel *channel = [SSHKitChannel sftpChannelFromSession:session delegate:self];
    if (!channel) {
        return nil;
    }
    if ([self initWithChannel:channel delegate:delegate]) {
        return self;
    } else {
        [channel close];
    }
    return nil;
}

- (BOOL)sftpInit {
    SSHKitChannel *channel = self.sshChannel;
    if (channel.stage == SSHKitChannelStageReadWrite) {
        _rawSFTPSession = sftp_new_channel(channel.session.rawSession, channel.rawChannel);
        if (self.rawSFTPSession == NULL) {
            // NSLog(@(ssh_get_error(session.rawSession)));
            return NO;
        }
        int rc = sftp_init(_rawSFTPSession);
        if (rc != SSH_OK) {
            // fprintf(stderr, "Error initializing SFTP session: %s.\n", sftp_get_error(sftp));
            sftp_free(_rawSFTPSession);
            _rawSFTPSession = NULL;
            // return rc;
            return NO;
        }
    }
    return YES;
}

- (void)close {
    if (self.rawSFTPSession) {
        sftp_free(self.rawSFTPSession);
    }
    self->_rawSFTPSession = NULL;
}

- (SSHKitSFTPFile *)openDirectory:(NSString *)path {
    SSHKitSFTPFile* directory = [[SSHKitSFTPFile alloc]init:self path:path isDirectory:YES];
    // TODO handle error
    [directory open];
    return directory;
}

- (SSHKitSFTPFile *)openFile:(NSString *)path {
    SSHKitSFTPFile* file = [[SSHKitSFTPFile alloc]init:self path:path isDirectory:NO];
    // TODO handle error
    [file open];
    return file;
}

#pragma mark SSHKitChannelDelegate

- (void)channelDidOpen:(SSHKitChannel *)channel {
    [self sftpInit];
    // TODO call delegate
}

@end
