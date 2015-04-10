#import <CoreFoundation/CoreFoundation.h>
#import <netinet/in.h>
#import <sys/socket.h>
#import <arpa/inet.h>
#import <libssh/libssh.h>
#import "SSHKitSession.h"
#import "SSHKitChannel.h"
#import "SSHKitPrivateKeyParser.h"
#import "SSHKitHostKeyParser.h"
#include <openssl/ec.h>
#include <openssl/dsa.h>
#include <openssl/rsa.h>

#define HAVE_OPENSSL_ECC 1
#define HAVE_LIBCRYPTO 1

#define SSHKIT_AGENT_IDENTITIES_ANSWER		12

struct ssh_key_struct {
    enum ssh_keytypes_e type;
    int flags;
    const char *type_c; /* Don't free it ! it is static */
    int ecdsa_nid;
#ifdef HAVE_LIBGCRYPT
    gcry_sexp_t dsa;
    gcry_sexp_t rsa;
    void *ecdsa;
#elif HAVE_LIBCRYPTO
    DSA *dsa;
    RSA *rsa;
#ifdef HAVE_OPENSSL_ECC
    EC_KEY *ecdsa;
#else
    void *ecdsa;
#endif /* HAVE_OPENSSL_EC_H */
#endif
    void *cert;
};

NSString * SSHKitGetBase64FromHostKey(ssh_key key);

#define SSHKit_CHANNEL_MAX_PACKET        32768
#define SSHKit_SESSION_DEFAULT_TIMEOUT   120 // two minutes

/*
 * 1. Session Queue could not dispatch write queue sync
 */

typedef NS_ENUM(NSInteger, SSHKitChannelDataType) {
    SSHKitChannelStdoutData  = 0,
    SSHKitChannelStderrData,
};

@interface SSHKitSession ()

/** Raw libssh session instance. */
@property (nonatomic, readonly) ssh_session rawSession;

- (void)addChannel:(SSHKitChannel *)channel;
- (void)removeChannel:(SSHKitChannel *)channel;

- (void)addForwardRequest:(NSArray *)forwardRequest;
- (void)removeForwardRequest:(NSArray *)forwardRequest;

@end

@interface SSHKitChannel ()

/** Raw libssh session instance. */
@property (nonatomic, readonly) ssh_channel rawChannel;

+ (instancetype)_tryCreateForwardChannelFromSession:(SSHKitSession *)session;
+ (void)_doRequestRemoteForwardOnSession:(SSHKitSession *)session withListenHost:(NSString *)host listenPort:(uint16_t)port completionHandler:(SSHKitRequestRemoteForwardCompletionBlock)completionHandler;

- (void)_doRead;
- (void)_doOpenDirect;
@end

@interface SSHKitPrivateKeyParser ()
{
    SSHKitAskPassphrasePrivateKeyBlock _passhpraseHandler;
}

@property (nonatomic, readonly) ssh_key privateKey;
@property (nonatomic, readonly) ssh_key publicKey;

@end

@interface SSHKitHostKeyParser ()

@property (nonatomic, readonly) ssh_key hostKey;
+ (instancetype)parserFromSSHKey:(ssh_key)sshKey error:(NSError **)errPtr;

@end

ssh_string pki_publickey_to_blob(const ssh_key key);
int buffer_add_u8(ssh_buffer buffer, uint8_t data);
int buffer_add_u32(ssh_buffer buffer, uint32_t data);
int buffer_add_ssh_string(ssh_buffer buffer, ssh_string string);
ssh_buffer ssh_buffer_new(void);
void ssh_buffer_free(ssh_buffer buffer);