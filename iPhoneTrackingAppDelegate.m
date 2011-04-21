//
//  iPhoneTracking HD
//
//  Originally created by Pete Warden on 4/15/11.
//  Modified by Justin Bull on 4/20/11.
//

#import "iPhoneTrackingAppDelegate.h"
#import "fmdb/FMDatabase.h"
#import "parsembdb.h"

@implementation iPhoneTrackingAppDelegate

@synthesize window;
@synthesize webView;

- (void)applicationDidFinishLaunching:(NSNotification *)aNotification {
}

- displayErrorAndQuit:(NSString *)error
{
    [[NSAlert alertWithMessageText: @"Error"
                     defaultButton:@"OK" alternateButton:nil otherButton:nil
         informativeTextWithFormat: error] runModal];
    exit(1);
}

- (void)awakeFromNib
{
    NSString* htmlString = [NSString stringWithContentsOfFile:[[NSBundle mainBundle] pathForResource:@"index" ofType:@"html"]
                                                     encoding:NSUTF8StringEncoding error:NULL];
    
 	[[webView mainFrame] loadHTMLString:htmlString baseURL:NULL];
    [webView setUIDelegate:self];
    [webView setFrameLoadDelegate:self]; 
    [webView setResourceLoadDelegate:self]; 
}

- (void)debugLog:(NSString *) message
{
    NSLog(@"%@", message);
}

+ (BOOL)isSelectorExcludedFromWebScript:(SEL)aSelector { return NO; }

- (void)webView:(WebView *)sender windowScriptObjectAvailable: (WebScriptObject *)windowScriptObject
{
    scriptObject = windowScriptObject;
}

- (void)webView:(WebView *)sender didFinishLoadForFrame:(WebFrame *)frame
{
    [self loadLocationDB];
}

- (void)loadLocationDB
{
    NSString* backupPath = [NSHomeDirectory() stringByAppendingPathComponent:@"Library/Application Support/MobileSync/Backup/"];
    
    NSFileManager *fm = [NSFileManager defaultManager];
    NSArray* backupContents = [[NSFileManager defaultManager] directoryContentsAtPath:backupPath];
    
    NSMutableArray* fileInfoList = [NSMutableArray array];
    for (NSString *childName in backupContents) {
        NSString* childPath = [backupPath stringByAppendingPathComponent:childName];
        
        NSString *plistFile = [childPath   stringByAppendingPathComponent:@"Info.plist"];
        
        NSError* error;
        NSDictionary *childInfo = [fm attributesOfItemAtPath:childPath error:&error];
        
        NSDate* modificationDate = [childInfo objectForKey:@"NSFileModificationDate"];    
        
        NSDictionary* fileInfo = [NSDictionary dictionaryWithObjectsAndKeys: 
                                  childPath, @"fileName", 
                                  modificationDate, @"modificationDate", 
                                  plistFile, @"plistFile", 
                                  nil];
        [fileInfoList addObject: fileInfo];
        
    }
    
    NSSortDescriptor* sortDescriptor = [[[NSSortDescriptor alloc] initWithKey:@"modificationDate" ascending:NO] autorelease];
    [fileInfoList sortUsingDescriptors:[NSArray arrayWithObject:sortDescriptor]];
    
    BOOL loadWorked = NO;
    for (NSDictionary* fileInfo in fileInfoList) {
        @try {
            NSString* newestFolder = [fileInfo objectForKey:@"fileName"];
            NSString* plistFile = [fileInfo objectForKey:@"plistFile"];
            
            NSDictionary *plist = [NSDictionary dictionaryWithContentsOfFile:plistFile];
            if (plist==nil) {
                NSLog(@"No plist file found at '%@'", plistFile);
                continue;
            }
            NSString* deviceName = [plist objectForKey:@"Device Name"];
            NSLog(@"file = %@, device = %@", plistFile, deviceName);  
            
            NSDictionary* mbdb = [ParseMBDB getFileListForPath: newestFolder];
            if (mbdb==nil) {
                NSLog(@"No MBDB file found at '%@'", newestFolder);
                continue;
            }
            
            NSString* wantedFileName = @"Library/Caches/locationd/consolidated.db";
            NSString* dbFileName = nil;
            for (NSNumber* offset in mbdb) {
                NSDictionary* fileInfo = [mbdb objectForKey:offset];
                NSString* fileName = [fileInfo objectForKey:@"filename"];
                if ([wantedFileName compare:fileName]==NSOrderedSame) {
                    dbFileName = [fileInfo objectForKey:@"fileID"];
                }
            }
            
            if (dbFileName==nil) {
                NSLog(@"No consolidated.db file found in '%@'", newestFolder);
                continue;
            }
            
            NSString* dbFilePath = [newestFolder stringByAppendingPathComponent:dbFileName];
            
            loadWorked = [self tryToLoadLocationDB: dbFilePath forDevice:deviceName];
            if (loadWorked) {
                break;
            }
        }
        @catch (NSException *exception) {
            NSLog(@"Exception: %@", [exception reason]);
        }
    }
    
    if (!loadWorked) {
        [self displayErrorAndQuit: [NSString stringWithFormat: @"Couldn't find iPhone location files on this machine.\n\nTried loading:\n%@/consolidated.db", backupPath]];  
    }
}

- (BOOL)tryToLoadLocationDB:(NSString*) locationDBPath forDevice:(NSString*) deviceName
{
    [scriptObject setValue:self forKey:@"cocoaApp"];
    
    FMDatabase* database = [FMDatabase databaseWithPath: locationDBPath];
    [database setLogsErrors: YES];
    BOOL openWorked = [database open];
    if (!openWorked) {
        return NO;
    }
    
    // This is the constant that controls the PoC's accuracy. Disabled to unleash full location data precision
    // const float precision = 100;
    NSMutableDictionary* events = [NSMutableDictionary dictionary];
    
    NSString* queries[] = {@"SELECT * FROM CellLocation;", @"SELECT * FROM WifiLocation;"};
    
    // Temporarily disabled WiFi location pulling, since it's so dodgy. Change to 
    for (int pass=0; pass<1; /*pass<2;*/ pass+=1) {
        
        FMResultSet* results = [database executeQuery:queries[pass]];
        
        while ([results next]) {
            NSDictionary* row = [results resultDict];
            
            NSNumber* latitude_number = [row objectForKey:@"latitude"];
            NSNumber* longitude_number = [row objectForKey:@"longitude"];
            NSNumber* timestamp_number = [row objectForKey:@"timestamp"];
            
            const float latitude = [latitude_number floatValue];
            const float longitude = [longitude_number floatValue];
            const float timestamp = [timestamp_number floatValue];
            
            // The timestamps seem to be based off 2001-01-01 strangely, so convert to the 
            // standard Unix form using this offset
            const float iOSToUnixOffset = (31*365.25*24*60*60);
            const float unixTimestamp = (timestamp+iOSToUnixOffset);
            
            if ((latitude==0.0)&&(longitude==0.0)) {
                continue;
            }
            
            //const float weekInSeconds = (7*24*60*60);
            const float timeEvent = unixTimestamp;
            
            NSDate* timeEventDate = [NSDate dateWithTimeIntervalSince1970:timeEvent];
            
            NSString* timeEventString = [timeEventDate descriptionWithCalendarFormat:@"%Y-%m-%d %H:%M:%S" timeZone:nil locale:nil];
            
            /* // Killed off obfuscation lines for full accuracy
             * const float latitude_index = (floor(latitude*precision)/precision);  
             * const float longitude_index = (floor(longitude*precision)/precision);
             */
            
            const float latitude_index = latitude;
            const float longitude_index = longitude;
            
            NSString* allKey = [NSString stringWithFormat:@"%f,%f,All Time", latitude_index, longitude_index];
            NSString* timeKey = [NSString stringWithFormat:@"%f,%f,%@", latitude_index, longitude_index, timeEventString];
            
            [self incrementEvents: events forKey: allKey];
            [self incrementEvents: events forKey: timeKey];
        }
    }
    
    NSMutableArray* csvArray = [[[NSMutableArray alloc] init] autorelease];
    
    [csvArray addObject: @"lat,lon,value,time\n"];
    
    for (NSString* key in events) {
        NSNumber* count = [events objectForKey:key];
        
        NSArray* parts = [key componentsSeparatedByString:@","];
        NSString* latitude_string = [parts objectAtIndex:0];
        NSString* longitude_string = [parts objectAtIndex:1];
        NSString* time_string = [parts objectAtIndex:2];
        
        NSString* rowString = [NSString stringWithFormat:@"%@,%@,%@,%@\n", latitude_string, longitude_string, count, time_string];
        [csvArray addObject: rowString];
    }
    
    if ([csvArray count]<10) {
        return NO;
    }
    
    NSString* csvText = [csvArray componentsJoinedByString:@"\n"];
    
    id scriptResult = [scriptObject callWebScriptMethod: @"storeLocationData" withArguments:[NSArray arrayWithObjects:csvText,deviceName,nil]];
	if(![scriptResult isMemberOfClass:[WebUndefined class]]) {
		NSLog(@"scriptResult='%@'", scriptResult);
    }
    
    return YES;
}

- (void) incrementEvents:(NSMutableDictionary*)events forKey:(NSString*)key
{
    NSNumber* existingValue = [events objectForKey:key];
    if (existingValue==nil) {
        existingValue = [NSNumber numberWithInteger:0];
    }
    NSNumber* newValue = [NSNumber numberWithInteger:([existingValue integerValue]+1)];
    
    [events setObject: newValue forKey: key];
}

- (IBAction)openAboutPanel:(id)sender {
    
    NSImage *img = [NSImage imageNamed: @"Icon"];
    NSDictionary *options = [NSDictionary dictionaryWithObjectsAndKeys:
                             @"1.0", @"Version",
                             @"iPhone Tracking HD", @"ApplicationName",
                             img, @"ApplicationIcon",
                             @"Copyright 2011, Justin Bull", @"Copyright",
                             @"iPhone Tracking HD v1.0", @"ApplicationVersion",
                             nil];
    
    [[NSApplication sharedApplication] orderFrontStandardAboutPanelWithOptions:options];
    
}
@end
