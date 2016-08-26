#import <Cordova/CDVPlugin.h>

@interface CDVMultipathTCP : CDVPlugin {
    NSString * _dl_progress_id;
}

- (void)download:(CDVInvokedUrlCommand*)command;

-(void)onDownloadProgress:(CDVInvokedUrlCommand*)command;

@end
