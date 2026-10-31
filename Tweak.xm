#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <QuartzCore/QuartzCore.h>
#import <CoreFoundation/CoreFoundation.h>
#import <unistd.h>

static CFStringRef const kPreferencesDomain =
    CFSTR("com.systemfps.preferences");

static CFStringRef const kReloadNotification =
    CFSTR("com.systemfps.preferences/reload");

static NSInteger gTargetFPS = 60;
static NSHashTable<CADisplayLink *> *gDisplayLinks;

static NSInteger SystemFPSClamp(NSInteger fps) {
    return MAX(25, MIN(60, fps));
}

static void SystemFPSLoadSettings(void) {
    NSInteger fps = 60;

    CFPropertyListRef value = CFPreferencesCopyAppValue(
        CFSTR("TargetFPS"),
        kPreferencesDomain
    );

    if (value != NULL) {
        if (CFGetTypeID(value) == CFNumberGetTypeID()) {
            CFNumberGetValue(
                (CFNumberRef)value,
                kCFNumberNSIntegerType,
                &fps
            );
        }
        CFRelease(value);
    }

    gTargetFPS = SystemFPSClamp(fps);
}

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

static void SystemFPSApplyToLink(CADisplayLink *link) {
    if (!link) return;

    SystemFPSLoadSettings();

    @try {
        [link setPreferredFramesPerSecond:gTargetFPS];
    }
    @catch (NSException *exception) {
        NSLog(@"[SystemFPS] Apply error: %@", exception);
    }
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

    NSLog(@"[SystemFPS] Updated FPS: %ld PID: %d",
          (long)gTargetFPS, getpid());
}

static void SystemFPSReloadCallback(
    CFNotificationCenterRef center,
    void *observer,
    CFStringRef name,
    const void *object,
    CFDictionaryRef userInfo
) {
    SystemFPSRefreshAllLinks();
}

%hook CADisplayLink

+ (CADisplayLink *)displayLinkWithTarget:(id)target
                                selector:(SEL)selector {
    CADisplayLink *link = %orig(target, selector);

    SystemFPSRegisterLink(link);
    SystemFPSApplyToLink(link);

    return link;
}

- (void)setPreferredFramesPerSecond:(NSInteger)framesPerSecond {
    SystemFPSLoadSettings();
    %orig(gTargetFPS);
}

- (void)setPreferredFrameRateRange:(CAFrameRateRange)range {
    SystemFPSLoadSettings();

    CAFrameRateRange limitedRange;
    limitedRange.minimum = (float)gTargetFPS;
    limitedRange.maximum = (float)gTargetFPS;
    limitedRange.preferred = (float)gTargetFPS;

    %orig(limitedRange);
}

- (void)addToRunLoop:(NSRunLoop *)runLoop
             forMode:(NSRunLoopMode)mode {
    %orig(runLoop, mode);

    SystemFPSRegisterLink(self);
    SystemFPSApplyToLink(self);
}

%end

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

        NSLog(@"[SystemFPS] Loaded FPS: %ld PID: %d",
              (long)gTargetFPS, getpid());
    }
}
