#import <arpa/inet.h>
#import <net/if.h>
#import <ifaddrs.h>
#import <netdb.h>
#import <sys/socket.h>
#import <netinet/in.h>
#import <sys/types.h>

#import "CDVMultipathTCP.h"

//private methods
@interface CDVMultipathTCP()
-(void)sendError:(NSString*)errorMessage forId:(NSString*)callbackId;
-(void)connectivityError:(NSString*)callbackId;
@end

@implementation CDVMultipathTCP
-(void)pluginInitialize
{
    _dl_progress_id = nil;
}

-(void)download:(CDVInvokedUrlCommand*)command
{
    [self.commandDelegate runInBackground:^{
        NSString *download_url = [command.arguments objectAtIndex:0];
        NSString *hostname, *filename;
        
        NSError *regex_error = NULL;
        NSString *url_regex_string = @"\\b^http:\\/\\/(.+\\.com)(\\/.+$)\\b";
        NSRegularExpression *url_regex = [NSRegularExpression
                                          regularExpressionWithPattern:url_regex_string
                                          options:0
                                          error:&regex_error];
        NSTextCheckingResult *url_match = [url_regex firstMatchInString:download_url
                                                                options:0
                                                                  range:NSMakeRange(0, [download_url length])];
        if (url_match) {
            hostname = [download_url substringWithRange:[url_match rangeAtIndex:1]];
            filename = [download_url substringWithRange:[url_match rangeAtIndex:2]];
        } else {
            [self sendError:@"Bad download URL format" forId:command.callbackId];
        }
        
        struct ifaddrs* addrs = 0;
        struct ifaddrs* bind_address = NULL;
        getifaddrs(&addrs);
        
        while(addrs) {
            int isUp = (addrs->ifa_flags & IFF_UP);
            int isIPv4 = (addrs->ifa_addr->sa_family == AF_INET);
            if (isUp == 1 && isIPv4 == 1 && strncmp("pdp_ip", addrs->ifa_name, 6) == 0) {
            //if (isUp == 1 && isIPv4 == 1 && strncmp("en", addrs->ifa_name, 2) == 0) {
                bind_address = addrs;
                break;
            }
            addrs = addrs->ifa_next;
        }
        
        if (bind_address == NULL) {
            [self sendError:@"Could not connect to the internet" forId:command.callbackId];
        }
        
        //get the destination address (didn't work)
        struct addrinfo* server_address;
        struct addrinfo hints = {0};
        hints.ai_family = AF_INET;
        hints.ai_socktype = SOCK_STREAM;
        hints.ai_protocol = IPPROTO_TCP;
        const char *hostname_as_cstr = [hostname cStringUsingEncoding:NSASCIIStringEncoding];
        if (getaddrinfo(hostname_as_cstr, "http", &hints, &server_address) != 0) {
            [self sendError:@"Could not resolve download url" forId:command.callbackId];
        }
        
        //  create a socket
        int request_socket = socket(hints.ai_family, hints.ai_socktype, hints.ai_protocol);
        if (bind(request_socket, bind_address->ifa_addr, sizeof(struct sockaddr_in)) < 0) {
            [self connectivityError: command.callbackId];
        };
        
        //connect to server
        if (connect(request_socket, server_address->ai_addr, server_address->ai_addrlen) < 0) {
            [self connectivityError:command.callbackId];
        }
        NSString *request = [NSString stringWithFormat:
                             @"GET %@ HTTP/1.1\r\nHost: %@\r\nAccept: */*\r\n\r\n"
                             , filename, hostname];
        const char *request_as_cstr = [request cStringUsingEncoding:NSASCIIStringEncoding];
        write(request_socket, request_as_cstr, strlen(request_as_cstr));
        
        //parse download header for content length
        size_t buffer_size=4096;
        char response_buffer[buffer_size];
        ssize_t recvd = read(request_socket, response_buffer, buffer_size);
        ssize_t header_size = 0;
        NSUInteger content_length = 0;
        
        NSString *response = [NSString stringWithCString:response_buffer encoding:NSASCIIStringEncoding];
        NSString *end_header_str = @"\\b\r\n\r\n\\b";
        NSRegularExpression *end_header_regex = [NSRegularExpression
                                                 regularExpressionWithPattern:end_header_str
                                                 options:0
                                                 error:&regex_error];
        NSRange header_range = [end_header_regex rangeOfFirstMatchInString:response
                                                                   options:0
                                                                     range:NSMakeRange(0, [response length])];
        if(!NSEqualRanges(header_range, NSMakeRange(NSNotFound, 0))) {
            header_size = header_range.location + header_range.length;
        } else {
            [self sendError:@"Failed To parse HTTP Headers" forId:command.callbackId];
        }
        
        NSString *content_length_str = @"\\bContent-Length:\\s(\\d+)\\r\\n\\b";
        NSRegularExpression *content_length_regex = [NSRegularExpression
                                                     regularExpressionWithPattern:content_length_str
                                                     options:0 error:&regex_error];
        NSTextCheckingResult *content_length_match = [content_length_regex firstMatchInString:response
                                                                                      options:0
                                                                                        range:NSMakeRange(0, [response length])];
        if(content_length_match){
            NSString *cl_str = [response substringWithRange:[content_length_match rangeAtIndex:1]];
            content_length = [cl_str integerValue];
        }
        else{
            [self sendError:@"Failed to Parse HTTP Headers for Content-Length" forId:command.callbackId];
        }
        
        char * firmware_buffer = malloc(content_length);
        
        size_t tot_recvd = recvd - header_size;
        memcpy(firmware_buffer, &(response_buffer[header_size]), tot_recvd);
        NSLog(@"tot_recvd: %zu", tot_recvd);
        
        size_t last_notification_size = 0;
        while((recvd = read(request_socket, response_buffer, buffer_size)) > 0 && tot_recvd < content_length) {
            memcpy(&firmware_buffer[tot_recvd], response_buffer, recvd);
            tot_recvd = tot_recvd + recvd;
            NSLog(@"tot_recvd: %zu", tot_recvd);
            if(_dl_progress_id != nil && tot_recvd - last_notification_size > 1000000){
                last_notification_size = tot_recvd;
                CDVPluginResult* result = [CDVPluginResult resultWithStatus:CDVCommandStatus_OK messageAsDouble:
                                           ((float)tot_recvd/content_length)];
                [result setKeepCallbackAsBool:YES];
                [self.commandDelegate sendPluginResult:result callbackId:_dl_progress_id];
            }
        }
        
        if(tot_recvd != content_length) {
            [self connectivityError:command.callbackId];
        } else if (_dl_progress_id != nil) {
            CDVPluginResult* result = [CDVPluginResult resultWithStatus:CDVCommandStatus_OK messageAsDouble:
                                       1.0];
            [result setKeepCallbackAsBool:YES];
            [self.commandDelegate sendPluginResult:result callbackId:_dl_progress_id];
        }
        
        close(request_socket);
        freeaddrinfo(server_address);
        
        CDVPluginResult* pluginResult = nil;
        NSData *fw_data = [NSData dataWithBytes:firmware_buffer length:content_length];
        free(firmware_buffer);
        
        pluginResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_OK messageAsArrayBuffer:fw_data];
        [self.commandDelegate sendPluginResult:pluginResult callbackId:command.callbackId];
    }];
  }

-(void)onDownloadProgress:(CDVInvokedUrlCommand *)command
{
    _dl_progress_id = command.callbackId;
}

-(void)sendError:(NSString*)errorMessage forId:(NSString*)callbackId
{
    CDVPluginResult *pluginResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_ERROR
                                                      messageAsString:errorMessage];
    [self.commandDelegate sendPluginResult:pluginResult callbackId:callbackId];
}

-(void)connectivityError:(NSString*)callbackId;
{
    CDVPluginResult *pluginResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_ERROR
                                                      messageAsString:@"Error Connecting To Remote Host"];
    [self.commandDelegate sendPluginResult:pluginResult callbackId:callbackId];
}

@end
