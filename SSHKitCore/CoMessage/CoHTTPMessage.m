#import "CoHTTPMessage.h"

#if ! __has_feature(objc_arc)
#warning This file must be compiled with ARC. Use -fobjc-arc flag (or convert project to ARC).
#endif


@implementation CoHTTPMessage

- (instancetype)initEmptyRequest
{
	if ((self = [super init]))
	{
		message = CFHTTPMessageCreateEmpty(NULL, YES);
	}
	return self;
}

- (instancetype)initRequestWithMethod:(NSString *)method URL:(NSString *)url version:(NSString *)version
{
	if ((self = [super init]))
	{
        message = CFHTTPMessageCreateEmpty(NULL, YES);
        
        // Create request header, avoid using CFHTTPMessageCreateRequest, it's not support CONNECT method
        NSString *header = [NSString stringWithFormat:@"%@ %@ %@", method, url, version];
        [self appendData:[header dataUsingEncoding:NSUTF8StringEncoding]];
	}
	return self;
}

- (instancetype)initResponseWithStatusCode:(NSInteger)code description:(NSString *)description version:(NSString *)version
{
	if ((self = [super init]))
	{
		message = CFHTTPMessageCreateResponse(NULL,
		                                      (CFIndex)code,
		                                      (__bridge CFStringRef)description,
		                                      (__bridge CFStringRef)version);
	}
	return self;
}

- (instancetype)initRequestWithData:(NSData *)data
{
    if ((self = [super init]))
    {
        message = CFHTTPMessageCreateEmpty(NULL, YES);
        CFHTTPMessageAppendBytes(message, [data bytes], [data length]);
    }
    return self;
}

- (instancetype)initResponseWithData:(NSData *)data
{
    if ((self = [super init]))
    {
        message = CFHTTPMessageCreateEmpty(NULL, NO);
        CFHTTPMessageAppendBytes(message, [data bytes], [data length]);
    }
    return self;
}

- (void)dealloc
{
	if (message)
	{
		CFRelease(message);
	}
}

- (BOOL)appendData:(NSData *)data
{
	return CFHTTPMessageAppendBytes(message, [data bytes], [data length]);
}

- (NSDictionary *)allHeaderFields
{
    return (__bridge_transfer NSDictionary *)CFHTTPMessageCopyAllHeaderFields(message);
}

- (NSString *)headerField:(NSString *)headerField
{
    return (__bridge_transfer NSString *)CFHTTPMessageCopyHeaderFieldValue(message, (__bridge CFStringRef)headerField);
}

- (void)setHeaderField:(NSString *)headerField value:(NSString *)headerFieldValue
{
    CFHTTPMessageSetHeaderFieldValue(message,
                                     (__bridge CFStringRef)headerField,
                                     (__bridge CFStringRef)headerFieldValue);
}

- (BOOL)addBasicAuthenticationWithUsername:(NSString *)username password:(NSString *)password forProxy:(BOOL)forProxy
{
    return CFHTTPMessageAddAuthentication(message, NULL, (__bridge CFStringRef)(username), (__bridge CFStringRef)(password), kCFHTTPAuthenticationSchemeBasic, forProxy);

}
- (BOOL)addAuthenticationWithFailureResponse:(CoHTTPMessage *)response username:(NSString *)username password:(NSString *)password forProxy:(BOOL)forProxy
{
    return CFHTTPMessageAddAuthentication(message, response.rawMessage, (__bridge CFStringRef)(username), (__bridge CFStringRef)(password), NULL, forProxy);
}

#pragma mark - Properties

- (BOOL)isHeaderComplete
{
	return CFHTTPMessageIsHeaderComplete(message);
}

- (NSString *)version
{
	return (__bridge_transfer NSString *)CFHTTPMessageCopyVersion(message);
}

- (NSString *)method
{
	return (__bridge_transfer NSString *)CFHTTPMessageCopyRequestMethod(message);
}

- (NSURL *)url
{
	return (__bridge_transfer NSURL *)CFHTTPMessageCopyRequestURL(message);
}

- (NSInteger)statusCode
{
	return (NSInteger)CFHTTPMessageGetResponseStatusCode(message);
}

- (NSString *)statusLine
{
    return (__bridge_transfer NSString *)CFHTTPMessageCopyResponseStatusLine(message);
}

- (NSData *)serializedData
{
	return (__bridge_transfer NSData *)CFHTTPMessageCopySerializedMessage(message);
}

- (NSData *)body
{
	return (__bridge_transfer NSData *)CFHTTPMessageCopyBody(message);
}

- (void)setBody:(NSData *)body
{
	CFHTTPMessageSetBody(message, (__bridge CFDataRef)body);
}

- (CFHTTPMessageRef)rawMessage
{
    return message;
}

@end
