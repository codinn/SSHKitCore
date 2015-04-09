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

typedef BIGNUM*  bignum;

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

int buffer_add_ssh_string(struct ssh_buffer_struct *buffer, struct ssh_string_struct *string);
void ssh_buffer_free(struct ssh_buffer_struct *buffer);
void *buffer_get_rest(struct ssh_buffer_struct *buffer);
uint32_t buffer_get_rest_len(struct ssh_buffer_struct *buffer);
ssh_string make_bignum_string(bignum num);
ssh_string ssh_string_new(size_t size);
ssh_buffer ssh_buffer_new(void);
ssh_string sshkit_pki_publickey_to_blob(const ssh_key key);