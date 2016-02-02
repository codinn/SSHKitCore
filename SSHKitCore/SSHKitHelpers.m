//
//  SSHKitHelpers.m
//  SSHKitCore
//
//  Created by Yang Yubo on 2/2/16.
//
//

#import "SSHKitHelpers.h"
#import "SSHKitSession.h"
#import "SSHKitCore+Protected.h"

@interface SSHKitForwardRequest()

@property (readwrite, copy) NSString    *listenHost;
@property (readwrite)       uint16_t    listenPort;
@property (readwrite, strong)       SSHKitRequestRemoteForwardCompletionBlock completionHandler;

@end

@implementation SSHKitForwardRequest

- (instancetype)initWithListenHost:(NSString *)host port:(uint16_t)port completionHandler:(SSHKitRequestRemoteForwardCompletionBlock)completionHandler {
    self = [super init];
    
    if (self) {
        if (!host.length) {
            self.listenHost = @"localhost";
        } else {
            self.listenHost = host.lowercaseString;
        }
        
        self.listenPort = port;
        self.completionHandler = completionHandler;
    }
    
    return self;
}

- (BOOL)isEqual:(id)object {
    return [self.listenHost isEqualToString:[object listenHost]] && self.listenPort==[object listenPort];
}

@end
