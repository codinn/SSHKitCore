/**
 * The HTTPMessage class is a simple Objective-C wrapper around Apple's CFHTTPMessage class.
**/

#import <Foundation/Foundation.h>

#if TARGET_OS_IPHONE
  // Note: You may need to add the CFNetwork Framework to your project
  #import <CFNetwork/CFNetwork.h>
#endif

#define HTTPVersion1_0  ((NSString *)kCFHTTPVersion1_0)
#define HTTPVersion1_1  ((NSString *)kCFHTTPVersion1_1)


@interface CoHTTPMessage : NSObject
{
	CFHTTPMessageRef message;
}

- (instancetype)initEmptyRequest;

- (instancetype)initRequestWithMethod:(NSString *)method URL:(NSString *)url version:(NSString *)version;

- (instancetype)initResponseWithStatusCode:(NSInteger)code description:(NSString *)description version:(NSString *)version;

- (instancetype)initResponseWithData:(NSData *)data;

- (BOOL)appendData:(NSData *)data;

- (NSDictionary *)allHeaderFields;
- (NSString *)headerField:(NSString *)headerField;

- (void)setHeaderField:(NSString *)headerField value:(NSString *)headerFieldValue;

- (BOOL)addBasicAuthenticationWithUsername:(NSString *)username password:(NSString *)password forProxy:(BOOL)forProxy;
- (BOOL)addAuthenticationWithFailureResponse:(CoHTTPMessage *)response username:(NSString *)username password:(NSString *)password forProxy:(BOOL)forProxy;

@property (readonly)    BOOL        isHeaderComplete;
@property (readonly)    NSString    *method;
@property (readonly)    NSString    *version;
@property (readonly)    NSURL       *url;
@property (readonly)    NSInteger   statusCode;
@property (readonly)    NSString    *statusLine;
@property (readonly)    NSData      *serializedData;
@property (readwrite)   NSData      *body;
@property (readonly)    CFHTTPMessageRef    rawMessage;

@end
