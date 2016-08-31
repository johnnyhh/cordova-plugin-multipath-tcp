#import <Cordova/CDVPlugin.h>

@interface CDVMultipathTCP : CDVPlugin {
    NSString * _dl_progress_id;
}

- (void)request:(CDVInvokedUrlCommand*)command;

-(void)onRequestProgress:(CDVInvokedUrlCommand*)command;

@end
