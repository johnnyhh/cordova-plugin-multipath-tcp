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

-(void)request:(CDVInvokedUrlCommand*)command
{
    [self.commandDelegate runInBackground:^{
        NSString *method = [command.arguments objectAtIndex:0];
        NSString *download_url = [command.arguments objectAtIndex:1];
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
            return;
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
            [self sendError:@"No available network interfaces" forId:command.callbackId];
            return;
        }
        
        //get the destination address (not working)
        //struct addrinfo* server_address;
        struct addrinfo hints = {0};
        hints.ai_family = AF_INET;
        hints.ai_socktype = SOCK_STREAM;
        hints.ai_protocol = IPPROTO_TCP;
        //const char *hostname_as_cstr = [hostname cStringUsingEncoding:NSASCIIStringEncoding];
        //int lookup_result = getaddrinfo(hostname_as_cstr, "http", &hints, &server_address);
        //if (server_address == NULL || lookup_result != 0) {
        //    [self sendError:@"Could not resolve download url" forId:command.callbackId];
        //    return;
        //}
        
        //hardcode server address temporarily
        //(getifaddrs tries to use dead wifi network instead of cell)
        struct sockaddr_in hardcoded_server_addr = {0};
        hardcoded_server_addr.sin_family = AF_INET;
        hardcoded_server_addr.sin_port = htons(80);
        if (inet_aton("198.199.115.18", &(hardcoded_server_addr.sin_addr)) != 1){
            [self sendError:@"failed to resolve host IP" forId:command.callbackId];
            return;
        }
        
        //  create a socket
        int request_socket = socket(hints.ai_family, hints.ai_socktype, hints.ai_protocol);
        if (bind(request_socket, bind_address->ifa_addr, sizeof(struct sockaddr_in)) < 0) {
            [self connectivityError: command.callbackId];
            return;
        };
        
        //connect to server
        //if (connect(request_socket, server_address->ai_addr, server_address->ai_addrlen) < 0) {
        if (connect(request_socket, (struct sockaddr *) &hardcoded_server_addr, sizeof(struct sockaddr_in)) < 0) {
            [self connectivityError:command.callbackId];
            return;
        }
        
        //Create Read+Write stream pair
        CFReadStreamRef read_stream;
        CFWriteStreamRef write_stream;
        CFStreamCreatePairWithSocket(kCFAllocatorDefault, request_socket, &read_stream, &write_stream);
        
        //Encode HTTP request
        CFURLRef req_url = CFURLCreateWithString(kCFAllocatorDefault, (__bridge CFStringRef)download_url, NULL);
        CFHTTPMessageRef http_request = CFHTTPMessageCreateRequest(kCFAllocatorDefault, (__bridge CFStringRef)method, req_url, kCFHTTPVersion1_1);
        CFHTTPMessageSetHeaderFieldValue(http_request, CFSTR("Host"), (__bridge CFStringRef)hostname);
        CFHTTPMessageSetHeaderFieldValue(http_request, CFSTR("Accept"), CFSTR("*/*"));
        
        //send http request with write stream
        if(!CFWriteStreamOpen(write_stream)){
            [self connectivityError:command.callbackId];
            return;
        }
        
        CFDataRef request_data = CFHTTPMessageCopySerializedMessage(http_request);
        CFIndex request_length = CFDataGetLength(request_data);
        UInt8 *request_buffer = malloc(request_length);
        CFDataGetBytes(request_data, CFRangeMake(0,request_length), request_buffer);
        if(CFWriteStreamWrite(write_stream, request_buffer, request_length) < 0 ){
            [self connectivityError:command.callbackId];
            return;
        }
        CFWriteStreamClose(write_stream);
        CFRelease(write_stream);
        free(request_buffer);
        
        //read response, building response object
        CFIndex buffer_length =4096;
        UInt8 response_buffer[buffer_length];
        CFHTTPMessageRef response = CFHTTPMessageCreateEmpty(kCFAllocatorDefault, FALSE);
        if(!CFReadStreamOpen(read_stream)){
            [self connectivityError:command.callbackId];
            return;
        }
        CFIndex num_bytes_read = 0;
        CFIndex content_length = 0;
        CFIndex total_bytes_read = 0;
        CFIndex last_notification_size = 0;
        bool headers_parsed = FALSE;
        do {
            num_bytes_read = CFReadStreamRead(read_stream, response_buffer, buffer_length);
            if(num_bytes_read > 0) {
                total_bytes_read += num_bytes_read;
                NSLog(@"Tot recvd: %ld", total_bytes_read);
                if (!CFHTTPMessageAppendBytes(response, response_buffer, num_bytes_read)){
                    [self connectivityError:command.callbackId];
                    return;
                }
                if (!headers_parsed && CFHTTPMessageIsHeaderComplete(response)) {
                    CFStringRef cl_str = CFHTTPMessageCopyHeaderFieldValue(response, CFSTR("Content-Length"));
                    content_length = CFStringGetIntValue(cl_str);
                }
                if (content_length > 0 && total_bytes_read - last_notification_size > 1000000){
                    last_notification_size = total_bytes_read;
                    CDVPluginResult* result = [CDVPluginResult resultWithStatus:CDVCommandStatus_OK messageAsDouble:
                                               ((float)total_bytes_read/content_length)];
                    [result setKeepCallbackAsBool:YES];
                    [self.commandDelegate sendPluginResult:result callbackId:_dl_progress_id];
                }
            } else if (num_bytes_read < 0) {
                [self connectivityError:command.callbackId];
                return;
            }
        } while( num_bytes_read > 0);
        
        if(total_bytes_read < content_length && [method  isEqual: @"GET"]) {
            [self connectivityError:command.callbackId];
            return;
        }
 
        //we need to return a javascript object with
        NSArray *plugin_response =
            @[[NSNumber numberWithLong:CFHTTPMessageGetResponseStatusCode(response)],
              (__bridge NSDictionary*)CFHTTPMessageCopyAllHeaderFields(response),
              (__bridge NSData*)CFHTTPMessageCopyBody(response)
              ];
        
        CDVPluginResult *plugin_result =
            [CDVPluginResult resultWithStatus:CDVCommandStatus_OK messageAsMultipart:plugin_response];
        [self.commandDelegate sendPluginResult:plugin_result callbackId:command.callbackId];
    }];
  }

-(void)onRequestProgress:(CDVInvokedUrlCommand *)command
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
