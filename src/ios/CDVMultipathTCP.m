#import <arpa/inet.h>
#import <net/if.h>
#import <ifaddrs.h>
#import <netdb.h>
#import <sys/socket.h>
#import <netinet/in.h>
#import <sys/types.h>

#import "CDVMultipathTCP.h"

@implementation CDVMultipathTCP

-(void)download:(CDVInvokedUrlCommand*)command
{
    struct ifaddrs* addrs = 0;
    getifaddrs(&addrs);
    
    while(addrs) {
        int isUp = (addrs->ifa_flags & IFF_UP);
        int isIPv4 = (addrs->ifa_addr->sa_family == AF_INET);
        //if (isUp == 1 && isIPv4 == 1 && strncmp("pdp_ip", addrs->ifa_name, 6) == 0) {
        if (isUp == 1 && isIPv4 == 1 && strncmp("en", addrs->ifa_name, 2) == 0) {
            NSLog(@"interface name: %s", addrs->ifa_name);
            break;
        }
        addrs = addrs->ifa_next;
    }
    
    //get the destination address (didn't work)
    struct addrinfo* server_address;
    struct addrinfo hints = {0};
    hints.ai_family = AF_INET;
    hints.ai_socktype = SOCK_STREAM;
    hints.ai_protocol = IPPROTO_TCP;
    getaddrinfo("firmware.rosepointnav.com", "http", &hints, &server_address);
    
    //  create a socket
    int request_socket = socket(hints.ai_family, hints.ai_socktype, hints.ai_protocol);
    int bindResult = bind(request_socket, addrs->ifa_addr, sizeof(struct sockaddr_in));
    NSLog(@"bind result for interface %s: %d", addrs->ifa_name, bindResult);
    
    //connect to server
    connect(request_socket, server_address->ai_addr, server_address->ai_addrlen);
    const char * request = "GET /ng1a/johnny.fw HTTP/1.1\r\nHost: firmware.rosepointnav.com\r\nAccept: */*\r\n\r\n";
    write(request_socket, request, strlen(request));
    
    //parse download header for content length
    size_t buffer_size=4096;
    char response_buffer[buffer_size];
    ssize_t recvd = read(request_socket, response_buffer, buffer_size);
    
    uint64_t content_length = 17993826;
    char * firmware_buffer = malloc(content_length);
    size_t header_size = 283;
    
    size_t tot_recvd = recvd - header_size;
    memcpy(firmware_buffer, &(response_buffer[header_size]), tot_recvd);
    //    memset(response_buffer, 0, buffer_size);
    NSLog(@"tot_recvd: %zu", tot_recvd);
    
    while(tot_recvd < content_length) {
        recvd = read(request_socket, response_buffer, buffer_size);
        memcpy(&firmware_buffer[tot_recvd], response_buffer, recvd);
        //        memset(response_buffer, 0, buffer_size);
        tot_recvd = tot_recvd + recvd;
        NSLog(@"tot_recvd: %zu", tot_recvd);
    }
    
    close(request_socket);
    freeaddrinfo(server_address);

    CDVPluginResult* pluginResult = nil;
    NSData *fw_data = [NSData dataWithBytes:firmware_buffer length:content_length];
    free(firmware_buffer);

    pluginResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_OK messageAsArrayBuffer:fw_data];
    [self.commandDelegate sendPluginResult:pluginResult callbackId:command.callbackId];
  }

  @end
