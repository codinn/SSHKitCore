//
//  SSHKitSFTPDirectory.m
//  SSHKitCore
//
//  Created by vicalloy on 8/28/15.
//
//

#import "SSHKitSFTPFile.h"
#import "SSHKitCore+Protected.h"
#import <sys/stat.h>

@interface SSHKitSFTPFile ()
@property (nonatomic, strong) NSString *fullFilename;
@property (nonatomic, strong) NSString *filename;
@property (nonatomic, readwrite) BOOL isDirectory;
@property (nonatomic, strong) NSDate *modificationDate;
@property (nonatomic, strong) NSDate *lastAccess;
@property (nonatomic, strong) NSNumber *fileSize;
@property (nonatomic, readwrite) unsigned long ownerUserID;
@property (nonatomic, readwrite) unsigned long ownerGroupID;
@property (nonatomic, strong) NSString *permissions;
@property (nonatomic, readwrite) u_long flags;
@end

@implementation SSHKitSFTPFile

- (instancetype)init:(SSHKitSFTP *)sftp path:(NSString *)path {
    if ((self = [super init])) {
        self.fullFilename = path;
        self.filename = [path lastPathComponent];
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

- (instancetype)initWithSFTPAttributes:(sftp_attributes)fileAttributes parentPath:(NSString *)parentPath {
    if ((self = [super init])) {
        [self populateValuesFromSFTPAttributes:fileAttributes parentPath:parentPath];
    }
    return self;
}

- (void)populateValuesFromSFTPAttributes:(sftp_attributes)fileAttributes parentPath:(NSString *)parentPath {
    NSString *filename = [NSString stringWithUTF8String:fileAttributes->name];
    self.filename = filename;
    self.fullFilename = [parentPath stringByAppendingString:filename];
    self.modificationDate = [NSDate dateWithTimeIntervalSince1970:fileAttributes->mtime];
    self.lastAccess = [NSDate dateWithTimeIntervalSinceNow:fileAttributes->atime];
    self.fileSize = @(fileAttributes->size);
    self.ownerUserID = fileAttributes->uid;
    self.ownerGroupID = fileAttributes->gid;
    self.permissions = [self convertPermissionToSymbolicNotation:fileAttributes->permissions];
    self->_fileTypeLetter = [self fileTypeLetter:fileAttributes->permissions];
    self.isDirectory = S_ISDIR(fileAttributes->permissions);
    self.flags = fileAttributes->flags;
}

- (NSInteger)closeDirectory {
    return sftp_closedir(self.rawDirectory);
}

- (BOOL)directoryEof {
    return sftp_dir_eof(self.rawDirectory);
}

- (SSHKitSFTPFile *)readDirectory {
    sftp_attributes attributes = sftp_readdir(self.sftp.rawSFTPSession, self.rawDirectory);
    return [[SSHKitSFTPFile alloc] initWithSFTPAttributes: attributes parentPath:self.filename];
}

#pragma mark - Permissions conversion methods

/**
 Convert a mode field into "ls -l" type perms field. By courtesy of Jonathan Leffler
 http://stackoverflow.com/questions/10323060/printing-file-permissions-like-ls-l-using-stat2-in-c
 
 @param mode The numeric mode that is returned by the 'stat' function
 @return A string containing the symbolic representation of the file permissions.
 */
- (NSString *)convertPermissionToSymbolicNotation:(unsigned long)mode {
    static char *rwx[] = {"---", "--x", "-w-", "-wx", "r--", "r-x", "rw-", "rwx"};
    char bits[11];
    
    bits[0] = [self fileTypeLetter:mode];
    strcpy(&bits[1], rwx[(mode >> 6)& 7]);
    strcpy(&bits[4], rwx[(mode >> 3)& 7]);
    strcpy(&bits[7], rwx[(mode & 7)]);
    
    if (mode & S_ISUID) {
        bits[3] = (mode & 0100) ? 's' : 'S';
    }
    
    if (mode & S_ISGID) {
        bits[6] = (mode & 0010) ? 's' : 'l';
    }
    
    if (mode & S_ISVTX) {
        bits[9] = (mode & 0100) ? 't' : 'T';
    }
    
    bits[10] = '\0';
    
    return [NSString stringWithCString:bits encoding:NSUTF8StringEncoding];
}

/**
 Extracts the unix letter for the file type of the given permission value.
 
 @param mode The numeric mode that is returned by the 'stat' function
 @return A character that represents the given file type.
 */
- (char)fileTypeLetter:(unsigned long)mode {
    char c;
    
    if (S_ISREG(mode)) {
        c = '-';
    }
    else if (S_ISDIR(mode)) {
        c = 'd';
    }
    else if (S_ISBLK(mode)) {
        c = 'b';
    }
    else if (S_ISCHR(mode)) {
        c = 'c';
    }
#ifdef S_ISFIFO
    else if (S_ISFIFO(mode)) {
        c = 'p';
    }
#endif
#ifdef S_ISLNK
    else if (S_ISLNK(mode)) {
        c = 'l';
    }
#endif
#ifdef S_ISSOCK
    else if (S_ISSOCK(mode)) {
        c = 's';
    }
#endif
#ifdef S_ISDOOR
    // Solaris 2.6, etc.
    else if (S_ISDOOR(mode)) {
        c = 'D';
    }
#endif
    else {
        // Unknown type -- possibly a regular file?
        c = '?';
    }
    
    return c;
}

- (NSString *)description {
    return [NSString stringWithFormat:@"<%@: %p> Filename: %@", NSStringFromClass([self class]), self, self.filename];
}

@end
