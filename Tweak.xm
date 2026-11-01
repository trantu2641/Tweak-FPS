
#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <QuartzCore/QuartzCore.h>
#import <CoreFoundation/CoreFoundation.h>
#import <objc/runtime.h>
#import <dispatch/dispatch.h>
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
static __thread BOOL gApplyingSystemFPS = NO;

static char kOriginalFPSKey;
static char kOriginalRangeKey;

#pragma mark - Current process

static NSString *SystemFPSCurrentBundleID(void) {
    return NSBundle.mainBundle.bundleIdentifier ?: @"";
}

#pragma mark - Settings

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

    NSString *bundleID = SystemFPSCurrentBundleID();

    CFPropertyListRef enabledValue =
        CFPreferencesCopyAppValue(
            kEnabledBundlesKey,
            kPreferencesDomain
        );

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

#pragma mark - Save original values

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

#pragma mark - Safe setters

static void SystemFPSSetFPS(
    CADisplayLink *link,
    NSInteger fps
) {
    if (!link) return;

    gApplyingSystemFPS = YES;

    @try {
        [link setPreferredFramesPerSecond:fps];
    }
    @finally {
        gApplyingSystemFPS = NO;
    }
}

static void SystemFPSSetRange(
    CADisplayLink *link,
    CAFrameRateRange range
) {
    if (!link) return;

    if (@available(iOS 15.0, *)) {
        gApplyingSystemFPS = YES;

        @try {
            [link setPreferredFrameRateRange:range];
        }
        @finally {
            gApplyingSystemFPS = NO;
        }
    }
}

#pragma mark - Apply FPS

static void SystemFPSApplyToLink(CADisplayLink *link) {
    if (!link) return;

    NSArray *savedRange =
        objc_getAssociatedObject(link, &kOriginalRangeKey);

    NSNumber *savedFPS =
        objc_getAssociatedObject(link, &kOriginalFPSKey);

    if (gSystemFPSEnabled) {

        if (@available(iOS 15.0, *)) {
            CAFrameRateRange range;

            range.minimum = (float)gTargetFPS;
            range.maximum = (float)gTargetFPS;
            range.preferred = (float)gTargetFPS;

            SystemFPSSetRange(link, range);
        } else {
            SystemFPSSetFPS(link, gTargetFPS);
        }

        return;
    }

    // Khôi phục range ban đầu.
    if ([savedRange isKindOfClass:NSArray.class] &&
        savedRange.count == 3) {

        CAFrameRateRange range;

        range.minimum = [savedRange[0] floatValue];
        range.maximum = [savedRange[1] floatValue];
        range.preferred = [savedRange[2] floatValue];

        SystemFPSSetRange(link, range);
        return;
    }

    // Khôi phục FPS ban đầu.
    if ([savedFPS isKindOfClass:NSNumber.class]) {
        SystemFPSSetFPS(link, savedFPS.integerValue);
        return;
    }

    // Không có cấu hình gốc: trả về tốc độ mặc định.
    SystemFPSSetFPS(link, 0);
}

#pragma mark - Refresh

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
        @"[SystemFPS] %@ | FPS:%ld | PID:%d | Bundle:%@ | Links:%lu",
        gSystemFPSEnabled ? @"ON" : @"OFF",
        (long)gTargetFPS,
        getpid(),
        SystemFPSCurrentBundleID(),
        (unsigned long)links.count
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

    if (link) {
        SystemFPSRegisterLink(link);

        SystemFPSLoadSettings();

        if (gSystemFPSEnabled) {
            SystemFPSApplyToLink(link);
        }
    }

    return link;
}

- (void)setPreferredFramesPerSecond:(NSInteger)framesPerSecond {

    if (!gApplyingSystemFPS) {
        SystemFPSStoreOriginalFPS(
            self,
            framesPerSecond
        );

        SystemFPSLoadSettings();
    }

    if (gSystemFPSEnabled && !gApplyingSystemFPS) {
        SystemFPSSetFPS(self, gTargetFPS);
        return;
    }

    %orig(framesPerSecond);
}

- (void)setPreferredFrameRateRange:(CAFrameRateRange)range {

    if (!gApplyingSystemFPS) {
        SystemFPSStoreOriginalRange(
            self,
            range
        );

        SystemFPSLoadSettings();
    }

    if (gSystemFPSEnabled && !gApplyingSystemFPS) {
        CAFrameRateRange limitedRange;

        limitedRange.minimum = (float)gTargetFPS;
        limitedRange.maximum = (float)gTargetFPS;
        limitedRange.preferred = (float)gTargetFPS;

        SystemFPSSetRange(self, limitedRange);
        return;
    }

    %orig(range);
}

- (void)addToRunLoop:(NSRunLoop *)runLoop
             forMode:(NSRunLoopMode)mode {

    %orig(runLoop, mode);

    SystemFPSRegisterLink(self);

    SystemFPSLoadSettings();

    if (gSystemFPSEnabled) {
        SystemFPSApplyToLink(self);
    }
}

%end

#pragma mark - Constructor

%ctor {
    @autoreleasepool {

        %init;

        SystemFPSInitRegistry();
        SystemFPSLoadSettings();

        CFNotificationCenterAddObserver(
            CFNotificationCenterGetDarwinNotifyCenter(),
            NULL,
            SystemFPSReloadCallback,
            kReloadNotification,
            NULL,
            CFNotificationSuspensionBehaviorDeliverImmediately
        );

        NSLog(
            @"[SystemFPS] SAFE CORE INITIALIZED | %@ | FPS:%ld | PID:%d | Bundle:%@",
            gSystemFPSEnabled ? @"ON" : @"OFF",
            (long)gTargetFPS,
            getpid(),
            SystemFPSCurrentBundleID()
        );
    }
}
