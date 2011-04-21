//
//  iPhoneTracking HD
//
//  Originally created by Pete Warden on 4/15/11.
//  Modified by Justin Bull on 4/20/11.
//

#import <Cocoa/Cocoa.h>
#import <WebKit/WebKit.h>

@interface iPhoneTrackingAppDelegate : NSObject <NSApplicationDelegate> {
  NSWindow *window;
  WebView *webView;
  WebScriptObject* scriptObject;
}

- (void)loadLocationDB;
- (BOOL)tryToLoadLocationDB:(NSString*) locationDBPath forDevice:(NSString*) deviceName;
- (void) incrementEvents:(NSMutableDictionary*)events forKey:(NSString*)key;

@property (assign) IBOutlet NSWindow *window;
@property (assign) IBOutlet WebView *webView;
- (IBAction)openAboutPanel:(id)sender;

@end
