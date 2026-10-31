
#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <QuartzCore/QuartzCore.h>
#import <CoreFoundation/CoreFoundation.h>

static NSString * const kDomain =
    @"com.systemfps.preferences";

static CFStringRef const kNotification =
    CFSTR("com.systemfps.preferences/reload");

static NSInteger gFPS = 60;

static NSHashTable<CADisplayLink *> *gLinks;

static NSInteger ClampFPS(NSInteger fps) {
    return MAX(25, MIN(60, fps));
}

static void LoadFPS(void) {
    CFPropertyListRef value = CFPreferencesCopyAppValue(
        CFSTR("TargetFPS"),
        CFSTR("com.systemfps.preferences")
    );

    NSInteger fps = 60;

    if (value) {
        if (CFGetTypeID(value) == CFNumberGetTypeID()) {
            CFNumberGetValue(
                (CFNumberRef)value,
                kCFNumberNSIntegerType,
                &fps
            );
        }
        CFRelease(value);
    }

    gFPS = ClampFPS(fps);
}

static void InitLinks(void) {
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        gLinks = [NSHashTable weakObjectsHashTable];
    });
}

static void RegisterLink(CADisplayLink *link) {
    if (!link) return;

    InitLinks();

    @synchronized (gLinks) {
        [gLinks addObject:link];
    }
}

static void ApplyLink(CADisplayLink *link) {
    if (!link) return;

    LoadFPS();
    [link setPreferredFramesPerSecond:gFPS];
}

static void UpdateLinks(void) {
    LoadFPS();
    InitLinks();

    NSArray *links;

    @synchronized (gLinks) {
        links = gLinks.allObjects;
    }

    for (CADisplayLink *link in links) {
        @try {
            [link setPreferredFramesPerSecond:gFPS];
        } @catch (NSException *e) {
            NSLog(@"[SystemFPS] %@", e);
        }
    }
}

static void ReloadNotification(
    CFNotificationCenterRef center,
    void *observer,
    CFStringRef name,
    const void *object,
    CFDictionaryRef userInfo
) {
    UpdateLinks();
}

%hook CADisplayLink

- (void)setPreferredFramesPerSecond:(NSInteger)fps {
    LoadFPS();
    %orig(gFPS);
}

- (void)setPreferredFrameRateRange:(CAFrameRateRange)range {
    LoadFPS();

    CAFrameRateRange fixed;
    fixed.minimum = (float)gFPS;
    fixed.maximum = (float)gFPS;
    fixed.preferred = (float)gFPS;

    %orig(fixed);
}

- (void)addToRunLoop:(NSRunLoop *)runLoop
             forMode:(NSRunLoopMode)mode {
    RegisterLink(self);
    ApplyLink(self);
    %orig;
}

%end

%ctor {
    @autoreleasepool {
        LoadFPS();
        InitLinks();

        CFNotificationCenterAddObserver(
            CFNotificationCenterGetDarwinNotifyCenter(),
            NULL,
            ReloadNotification,
            kNotification,
            NULL,
            CFNotificationSuspensionBehaviorDeliverImmediately
        );

        NSLog(@"[SystemFPS] Loaded at %ld FPS",
              (long)gFPS);
    }
}
