#import <Foundation/Foundation.h>
#import <CoreFoundation/CoreFoundation.h>
#import <roothide.h>
#import <unistd.h>

static CFStringRef const kNotification =
    CFSTR("com.systemfps.preferences/reload");

#pragma mark - Paths

// Preferences nằm trên filesystem dữ liệu người dùng.
// Không dùng jbroot() cho đường dẫn này.
static NSString *SystemFPSPreferencesPath(void) {
    return @"/var/mobile/Library/Preferences/com.systemfps.preferences.plist";
}

// Filter nằm trong jailbreak root nên phải dùng jbroot().
static NSString *SystemFPSFilterPath(void) {
    const char *path =
        jbroot("/Library/MobileSubstrate/DynamicLibraries/SystemFPS.plist");

    return path ? [NSString stringWithUTF8String:path] : nil;
}

#pragma mark - Read preferences

static NSArray *SystemFPSReadEnabledBundles(void) {
    NSString *path = SystemFPSPreferencesPath();

    NSDictionary *preferences =
        [NSDictionary dictionaryWithContentsOfFile:path];

    id value = preferences[@"EnabledBundleIDs"];

    NSMutableArray *bundles = [NSMutableArray array];

    // SpringBoard luôn được giữ mặc định nếu chưa có cấu hình.
    if (![value isKindOfClass:NSArray.class]) {
        return @[@"com.apple.springboard"];
    }

    for (id item in (NSArray *)value) {
        if (![item isKindOfClass:NSString.class]) {
            continue;
        }

        NSString *bundleID = (NSString *)item;

        if (bundleID.length == 0) {
            continue;
        }

        if (![bundles containsObject:bundleID]) {
            [bundles addObject:bundleID];
        }
    }

    return bundles;
}

#pragma mark - Update ElleKit filter

static BOOL SystemFPSWriteFilter(void) {
    NSArray *bundles = SystemFPSReadEnabledBundles();

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

    if (path.length == 0) {
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
        [data writeToFile:path
                  options:NSDataWritingAtomic
                    error:&error];

    if (!success) {
        NSLog(@"[SystemFPSDaemon] Write failed: %@", error);
        return NO;
    }

    NSLog(@"[SystemFPSDaemon] Filter updated: %@", bundles);

    return YES;
}

#pragma mark - Notification

static void SystemFPSNotificationCallback(
    CFNotificationCenterRef center,
    void *observer,
    CFStringRef name,
    const void *object,
    CFDictionaryRef userInfo
) {
    SystemFPSWriteFilter();
}

#pragma mark - Main

int main(int argc, char *argv[]) {
    @autoreleasepool {
        NSLog(@"[SystemFPSDaemon] Starting");

        // Cập nhật filter khi daemon khởi động.
        SystemFPSWriteFilter();

        // Theo dõi thay đổi công tắc trong Settings.
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
