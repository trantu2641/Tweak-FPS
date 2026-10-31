#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <QuartzCore/QuartzCore.h>
#import <CoreFoundation/CoreFoundation.h>
#import <objc/runtime.h>
#import <unistd.h>

static CFStringRef const kPreferencesDomain =
    CFSTR("com.systemfps.preferences");

static CFStringRef const kReloadNotification =
    CFSTR("com.systemfps.preferences/reload");

static CFStringRef const kEnabledBundlesKey =
    CFSTR("EnabledBundleIDs");

static NSInteger gTargetFPS = 60;
static BOOL gSystemFPSEnabled = NO;

static NSHashTable<CADisplayLink *> *gDisplayLinks;

// Phân biệt lệnh do tweak gọi và lệnh do ứng dụng gọi.
static __thread BOOL gApplyingSystemFPS = NO;

// Lưu FPS gốc của từng CADisplayLink.
static char kOriginalFPSKey;
static char kOriginalRangeKey;

#pragma mark - Current process

static NSString *SystemFPSCurrentBundleID(void) {
    NSString *bundleID = NSBundle.mainBundle.bundleIdentifier;

    return bundleID ?: @"";
}

#pragma mark - Preferences

static NSInteger SystemFPSClamp(NSInteger fps) {
    return MAX(25, MIN(60, fps));
}

static void SystemFPSLoadSettings(void) {
    NSInteger fps = 60;

    CFPropertyListRef fpsValue =
        CFPreferencesCopyAppValue(
            CFSTR("TargetFPS"),
            kPreferencesDomain
        );

    if (fpsValue) {
        if (CFGetTypeID(fpsValue) == CFNumberGetTypeID()) {
            CFNumberGetValue(
                (CFNumberRef)fpsValue,
                kCFNumberNSIntegerType,
                &fps
            );
        }

        CFRelease(fpsValue);
    }

    gTargetFPS = SystemFPSClamp(fps);

    CFPropertyListRef enabledValue =
        CFPreferencesCopyAppValue(
            kEnabledBundlesKey,
            kPreferencesDomain
        );

    NSString *bundleID = SystemFPSCurrentBundleID();

    // Lần đầu cài đặt: giữ SpringBoard bật như cấu hình cũ.
    if (!enabledValue) {
        gSystemFPSEnabled =
            [bundleID isEqualToString:@"com.apple.springboard"];
        return;
    }

    gSystemFPSEnabled = NO;

    if (CFGetTypeID(enabledValue) == CFArrayGetTypeID()) {
        NSArray *enabledBundles =
            (__bridge NSArray *)enabledValue;

        gSystemFPSEnabled =
            [enabledBundles containsObject:bundleID];
    }

    CFRelease(enabledValue);
}

#pragma mark - Registry

static void SystemFPSInitRegistry(void) {
    static dispatch_once_t onceToken;

    dispatch_once(&onceToken, ^{
        gDisplayLinks = [NSHashTable weakObjectsHashTable];
    });
}

static void SystemFPSRegisterLink(CADisplayLink *link) {
    if (!link) return;

    SystemFPSInitRegistry();

    @synchronized (gDisplayLinks) {
        [gDisplayLinks addObject:link];
    }
}

#pragma mark - Original FPS storage

static void SystemFPSStoreOriginalFPS(
    CADisplayLink *link,
    NSInteger fps
) {
    objc_setAssociatedObject(
        link,
        &kOriginalFPSKey,
        @(fps),
        OBJC_ASSOCIATION_RETAIN_NONATOMIC
    );

    objc_setAssociatedObject(
        link,
        &kOriginalRangeKey,
        nil,
        OBJC_ASSOCIATION_RETAIN_NONATOMIC
    );
}

static void SystemFPSStoreOriginalRange(
    CADisplayLink *link,
    CAFrameRateRange range
) {
    NSArray *values = @[
        @(range.minimum),
        @(range.maximum),
        @(range.preferred)
    ];

    objc_setAssociatedObject(
        link,
        &kOriginalRangeKey,
        values,
        OBJC_ASSOCIATION_RETAIN_NONATOMIC
    );

    objc_setAssociatedObject(
        link,
        &kOriginalFPSKey,
        nil,
        OBJC_ASSOCIATION_RETAIN_NONATOMIC
    );
}

#pragma mark - Apply and restore

static void SystemFPSApplyToLink(CADisplayLink *link) {
    if (!link) return;

    SystemFPSLoadSettings();

    gApplyingSystemFPS = YES;

    if (gSystemFPSEnabled) {
        [link setPreferredFramesPerSecond:gTargetFPS];
    } else {
        NSArray *savedRange = objc_getAssociatedObject(
            link,
            &kOriginalRangeKey
        );

        NSNumber *savedFPS = objc_getAssociatedObject(
            link,
            &kOriginalFPSKey
        );

        if ([savedRange isKindOfClass:NSArray.class] &&
            savedRange.count == 3) {

            CAFrameRateRange range;

            range.minimum = [savedRange[0] floatValue];
            range.maximum = [savedRange[1] floatValue];
            range.preferred = [savedRange[2] floatValue];

            [link setPreferredFrameRateRange:range];

        } else if ([savedFPS isKindOfClass:NSNumber.class]) {

            [link setPreferredFramesPerSecond:savedFPS.integerValue];

        } else {

            // Giá trị 0 trả quyền lựa chọn FPS về hệ thống.
            [link setPreferredFramesPerSecond:0];
        }
    }

    gApplyingSystemFPS = NO;
}

static void SystemFPSRefreshAllLinks(void) {
    SystemFPSLoadSettings();
    SystemFPSInitRegistry();

    NSArray<CADisplayLink *> *links;

    @synchronized (gDisplayLinks) {
        links = gDisplayLinks.allObjects;
    }

    for (CADisplayLink *link in links) {
        SystemFPSApplyToLink(link);
    }

    NSLog(
        @"[SystemFPS] %@ | FPS: %ld | PID: %d | Bundle: %@",
        gSystemFPSEnabled ? @"ON" : @"OFF",
        (long)gTargetFPS,
        getpid(),
        SystemFPSCurrentBundleID()
    );
}

#pragma mark - Notification

static void SystemFPSReloadCallback(
    CFNotificationCenterRef center,
    void *observer,
    CFStringRef name,
    const void *object,
    CFDictionaryRef userInfo
) {
    SystemFPSRefreshAllLinks();
}

#pragma mark - CADisplayLink hooks

%hook CADisplayLink

+ (CADisplayLink *)displayLinkWithTarget:(id)target
                                selector:(SEL)selector {

    CADisplayLink *link = %orig(target, selector);

    SystemFPSRegisterLink(link);
    SystemFPSApplyToLink(link);

    return link;
}

- (void)setPreferredFramesPerSecond:(NSInteger)framesPerSecond {

    if (!gApplyingSystemFPS) {
        SystemFPSStoreOriginalFPS(self, framesPerSecond);
    }

    SystemFPSLoadSettings();

    if (gSystemFPSEnabled && !gApplyingSystemFPS) {
        %orig(gTargetFPS);
    } else {
        %orig(framesPerSecond);
    }
}

- (void)setPreferredFrameRateRange:(CAFrameRateRange)range {

    if (!gApplyingSystemFPS) {
        SystemFPSStoreOriginalRange(self, range);
    }

    SystemFPSLoadSettings();

    if (gSystemFPSEnabled && !gApplyingSystemFPS) {

        CAFrameRateRange limitedRange;

        limitedRange.minimum = (float)gTargetFPS;
        limitedRange.maximum = (float)gTargetFPS;
        limitedRange.preferred = (float)gTargetFPS;

        %orig(limitedRange);

    } else {

        %orig(range);
    }
}

- (void)addToRunLoop:(NSRunLoop *)runLoop
             forMode:(NSRunLoopMode)mode {

    %orig(runLoop, mode);

    SystemFPSRegisterLink(self);
    SystemFPSApplyToLink(self);
}

%end

#pragma mark - Constructor

%ctor {
    @autoreleasepool {

        SystemFPSLoadSettings();
        SystemFPSInitRegistry();

        CFNotificationCenterAddObserver(
            CFNotificationCenterGetDarwinNotifyCenter(),
            NULL,
            SystemFPSReloadCallback,
            kReloadNotification,
            NULL,
            CFNotificationSuspensionBehaviorDeliverImmediately
        );

        NSLog(
            @"[SystemFPS] Loaded | %@ | FPS: %ld | PID: %d | Bundle: %@",
            gSystemFPSEnabled ? @"ON" : @"OFF",
            (long)gTargetFPS,
            getpid(),
            SystemFPSCurrentBundleID()
        );
    }
}
