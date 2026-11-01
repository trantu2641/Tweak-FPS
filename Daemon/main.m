
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

static NSDictionary *SystemFPSCreateFilter(void) {
    return @{
        @"Filter": @{
            @"Bundles": @[
                @"com.apple.springboard",
                @"com.apple.UIKit"
            ]
        }
    };
}

static void SystemFPSWriteFilter(void) {
    NSDictionary *filter = SystemFPSCreateFilter();

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
        NSLog(
            @"[SystemFPSDaemon] Invalid filter path"
        );

        return;
    }

    BOOL success =
        [data writeToFile:path
                  options:NSDataWritingAtomic
                    error:&error];

    if (success) {
        NSLog(
            @"[SystemFPSDaemon] Filter updated: %@",
            path
        );
    } else {
        NSLog(
            @"[SystemFPSDaemon] Filter write failed: %@",
            error
        );
    }
}

int main(int argc, char *argv[]) {
    @autoreleasepool {
        SystemFPSWriteFilter();
    }

    return 0;
}
