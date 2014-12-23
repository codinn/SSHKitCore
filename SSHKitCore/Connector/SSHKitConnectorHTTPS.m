//
//  SSHKitConnectorHTTPS.m
//  sshproxy
//
//  Created by Yang Yubo on 11/21/14.
//  Copyright (c) 2014 Codinn. All rights reserved.
//

#import <Foundation/Foundation.h>
#import <Foundation/Foundation.h>
#import <arpa/inet.h>
#import "SSHKitConnectorProxy.h"
#import "SSHKitConnector+Protected.h"
#import "CoSocket.h"
#import "CoHTTPMessage.h"

#define CSConnectHTTPSDomain @"CSConnect.HTTPS"

static CoHTTPMessage *buildRequestMessage(NSString *targetHost, uint16_t targetPort)
{
    NSURL *proxyURL = [NSURL URLWithString:[[NSString alloc] initWithFormat:@"%@:%d", targetHost, targetPort]];
    return [[CoHTTPMessage alloc] initRequestWithMethod:@"CONNECT" URL:proxyURL version:HTTPVersion1_0];
}


@implementation SSHKitConnectorHTTPS

/* begin HTTPS protocol CONNECT relaying
 */

- (BOOL)connectToTarget:(NSString *)host onPort:(uint16_t)port error:(NSError **)errPtr
{
    self.targetHost = host;
    self.targetPort = port;
    
    BOOL forProxy = YES;
    
    _coSocket = [[CoSocket alloc] initWithHost:self.proxyHost onPort:self.proxyPort];
    
    if (![_coSocket connect]) {
        if (errPtr) *errPtr = _coSocket.lastError;
        return NO;
    }
    
    /**
     * Sends the HTTPS connect data (according to XEP-65), and starts reading the response.
     **/
    CoHTTPMessage *request = buildRequestMessage(self.targetHost, self.targetPort);
    
    if (self.proxyUsername.length && self.proxyPassword.length) {
        [request addBasicAuthenticationWithUsername:self.proxyUsername password:self.proxyPassword forProxy:forProxy];
    }
    
    if (![_coSocket writeData:request.serializedData]) {
        if (errPtr) *errPtr = _coSocket.lastError;
        return NO;
    }
    
    // Now we tell the socket to read the full header for the http response.
    // As per the http protocol, we know the header is terminated with two CRLF's (carriage return, line feed).
    
    NSData *responseTerminatorData = [@"\r\n\r\n" dataUsingEncoding:NSASCIIStringEncoding];
    
    NSData *responseData = [_coSocket readDataToData:responseTerminatorData];
        
    if (!responseData.length) {
        if (errPtr) *errPtr = _coSocket.lastError;
        return NO;
    }
    
    NSString *failureReason = nil;
    CoHTTPMessage *response = [[CoHTTPMessage alloc] initResponseWithData:responseData];
    NSInteger statusCode = response.statusCode;
    
    switch (statusCode) {
        case 200:   /* sucess */
        case 201:
        case 202:
            break;
            
            /* We handle both 401 and 407 codes here: 401 is WWW-Authenticate, which
             * not strictly the correct response, but some proxies do send this (e.g.
             * Symantec's Raptor firewall) */
        case 405:
            failureReason = [NSString stringWithFormat:@"HTTPS Proxy: CONNECT method not allowed (%@:%u)", self.proxyHost, self.proxyPort];
            break;
            
        case 401:
        case 407:
            // BOOL forProxy = statusCode==401 ? YES : NO;
            failureReason = [NSString stringWithFormat:@"HTTPS Proxy: authentication failed (%@:%u)", self.proxyHost, self.proxyPort];
            
            break;
            
        default:
            failureReason = [NSString stringWithFormat:@"HTTPS Proxy: unexpected response '%@' (%@:%u)", response.statusLine, self.proxyHost, self.proxyPort];
            break;
    }
    
    if (failureReason) {
        // todo: error code should replaced by a macro
        if (errPtr) *errPtr = [NSError errorWithDomain:CSConnectHTTPSDomain
                                           code:6
                                       userInfo:@{ NSLocalizedDescriptionKey : failureReason }];
        return NO;
    }
    
    return YES;
}

@end
