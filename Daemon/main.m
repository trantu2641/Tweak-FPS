
#import <Foundation/Foundation.h>
#import <CoreFoundation/CoreFoundation.h>
#import <roothide.h>

static NSString *SystemFPSFilterPath(void) {
    const char *path =
        jbroot("/Library/MobileSubstrate/DynamicLibraries/SystemFPS.plist");

    if (!path) {
        return nil;
    }

    return [NSString stringWithUTF8String:path];
}

static void SystemFPSWriteFilter(void) {
    NSDictionary *filter = @{
        @"Filter": @{
            @"Bundles": @[
                @"com.apple.UIKit",
                @"com.apple.springboard"
            ]
        }
    };

    NSError *error = nil;

    NSData *data =
        [NSPropertyListSerialization
            dataWithPropertyList:filter
            format:NSPropertyListXMLFormat_v1_0
            options:0
            error:&error];

    if (!data) {
        NSLog(
            @"[SystemFPSDaemon] Serialization failed: %@",
            error
        );
        return;
    }

    NSString *path = SystemFPSFilterPath();

    if (!path) {
        NSLog(@"[SystemFPSDaemon] Invalid filter path");
        return;
    }

    BOOL success =
        [data writeToFile:path
                  options:NSDataWritingAtomic
                    error:&error];

    NSLog(
        @"[SystemFPSDaemon] Filter %@: %@",
        success ? @"updated" : @"failed",
        error ?: path
    );
}

int main(int argc, char *argv[]) {
    @autoreleasepool {
        SystemFPSWriteFilter();
    }

    return 0;
}
