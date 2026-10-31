#import <Foundation/Foundation.h>
#import <CoreFoundation/CoreFoundation.h>
#import <roothide.h>
#import <unistd.h>

static CFStringRef const kNotification =
    CFSTR("com.systemfps.preferences/reload");

static NSString *SystemFPSPreferencesPath(void) {
    const char *path =
        jbroot("/var/mobile/Library/Preferences/com.systemfps.preferences.plist");

    return path ? [NSString stringWithUTF8String:path] : nil;
}

static NSString *SystemFPSFilterPath(void) {
    const char *path =
        jbroot("/Library/MobileSubstrate/DynamicLibraries/SystemFPS.plist");

    return path ? [NSString stringWithUTF8String:path] : nil;
}

static NSArray *SystemFPSReadEnabledBundles(void) {
    NSString *path = SystemFPSPreferencesPath();

    NSDictionary *preferences =
        [NSDictionary dictionaryWithContentsOfFile:path];

    id value = preferences[@"EnabledBundleIDs"];

    if (![value isKindOfClass:NSArray.class]) {
        return @[@"com.apple.springboard"];
    }

    NSMutableArray *result =
        [NSMutableArray array];

    for (id item in (NSArray *)value) {
        if ([item isKindOfClass:NSString.class] &&
            [item length] > 0 &&
            ![result containsObject:item]) {
            [result addObject:item];
        }
    }

    return result;
}

static BOOL SystemFPSWriteFilter(void) {
    NSArray *bundles =
        SystemFPSReadEnabledBundles();

    NSDictionary *filter = @{
        @"Filter": @{
            @"Bundles": bundles
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
        NSLog(@"[SystemFPSDaemon] Plist error: %@", error);
        return NO;
    }

    NSString *path = SystemFPSFilterPath();

    if (!path) {
        NSLog(@"[SystemFPSDaemon] Cannot resolve filter path");
        return NO;
    }

    NSString *directory =
        [path stringByDeletingLastPathComponent];

    [[NSFileManager defaultManager]
        createDirectoryAtPath:directory
        withIntermediateDirectories:YES
        attributes:nil
        error:nil];

    BOOL success =
        [data writeToFile:path options:NSDataWritingAtomic error:&error];

    if (!success) {
        NSLog(@"[SystemFPSDaemon] Write error: %@", error);
        return NO;
    }

    NSLog(
        @"[SystemFPSDaemon] Filter updated: %@",
        bundles
    );

    return YES;
}

static void SystemFPSNotificationCallback(
    CFNotificationCenterRef center,
    void *observer,
    CFStringRef name,
    const void *object,
    CFDictionaryRef userInfo
) {
    SystemFPSWriteFilter();
}

int main(int argc, char *argv[]) {
    @autoreleasepool {
        NSLog(@"[SystemFPSDaemon] Starting");

        // Cập nhật ngay khi daemon khởi động.
        SystemFPSWriteFilter();

        CFNotificationCenterAddObserver(
            CFNotificationCenterGetDarwinNotifyCenter(),
            NULL,
            SystemFPSNotificationCallback,
            kNotification,
            NULL,
            CFNotificationSuspensionBehaviorDeliverImmediately
        );

        CFRunLoopRun();
    }

    return 0;
}
