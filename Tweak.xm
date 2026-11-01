
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
static NSHashTable<CAAnimation *> *gAnimations;

static __thread BOOL gApplyingLinkFPS = NO;
static __thread BOOL gApplyingAnimationFPS = NO;

static char kOriginalLinkRangeKey;
static char kOriginalLinkFPSKey;
static char kOriginalAnimationRangeKey;

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

    CFPropertyListRef enabledValue =
        CFPreferencesCopyAppValue(
            kEnabledBundlesKey,
            kPreferencesDomain
        );

    NSString *bundleID = SystemFPSCurrentBundleID();

    BOOL enabled =
        [bundleID isEqualToString:@"com.apple.springboard"];

    if (enabledValue &&
        CFGetTypeID(enabledValue) == CFArrayGetTypeID()) {

        NSArray *enabledBundles =
            (__bridge NSArray *)enabledValue;

        enabled = [enabledBundles containsObject:bundleID];
    }

    if (enabledValue) {
        CFRelease(enabledValue);
    }

    gSystemFPSEnabled = enabled;
}

#pragma mark - Frame rate range

static CAFrameRateRange SystemFPSLimitRange(
    CAFrameRateRange requested
) {
    float limit = (float)gTargetFPS;

    CAFrameRateRange result;

    float maximum = requested.maximum;

    if (!(maximum > 0.0f) || maximum > limit) {
        maximum = limit;
    }

    float minimum = requested.minimum;

    if (!(minimum >= 0.0f)) {
        minimum = 0.0f;
    }

    if (minimum > maximum) {
        minimum = maximum;
    }

    float preferred = requested.preferred;

    if (!(preferred > 0.0f) || preferred > maximum) {
        preferred = maximum;
    }

    if (preferred < minimum) {
        preferred = minimum;
    }

    result.minimum = minimum;
    result.maximum = maximum;
    result.preferred = preferred;

    return result;
}

static NSArray *SystemFPSValuesFromRange(
    CAFrameRateRange range
) {
    return @[
        @(range.minimum),
        @(range.maximum),
        @(range.preferred)
    ];
}

static BOOL SystemFPSRangeFromValues(
    id values,
    CAFrameRateRange *range
) {
    if (![values isKindOfClass:NSArray.class] ||
        [(NSArray *)values count] != 3) {
        return NO;
    }

    NSArray *items = (NSArray *)values;

    range->minimum = [items[0] floatValue];
    range->maximum = [items[1] floatValue];
    range->preferred = [items[2] floatValue];

    return YES;
}

#pragma mark - Registry

static void SystemFPSInitRegistry(void) {
    static dispatch_once_t onceToken;

    dispatch_once(&onceToken, ^{
        gDisplayLinks = [NSHashTable weakObjectsHashTable];
        gAnimations = [NSHashTable weakObjectsHashTable];
    });
}

static void SystemFPSRegisterLink(CADisplayLink *link) {
    if (!link) return;

    SystemFPSInitRegistry();

    @synchronized (gDisplayLinks) {
        [gDisplayLinks addObject:link];
    }
}

static void SystemFPSRegisterAnimation(CAAnimation *animation) {
    if (!animation) return;

    SystemFPSInitRegistry();

    @synchronized (gAnimations) {
        [gAnimations addObject:animation];
    }
}

#pragma mark - Original CADisplayLink values

static void SystemFPSStoreOriginalLinkFPS(
    CADisplayLink *link,
    NSInteger fps
) {
    objc_setAssociatedObject(
        link,
        &kOriginalLinkFPSKey,
        @(fps),
        OBJC_ASSOCIATION_RETAIN_NONATOMIC
    );

    objc_setAssociatedObject(
        link,
        &kOriginalLinkRangeKey,
        nil,
        OBJC_ASSOCIATION_RETAIN_NONATOMIC
    );
}

static void SystemFPSStoreOriginalLinkRange(
    CADisplayLink *link,
    CAFrameRateRange range
) {
    objc_setAssociatedObject(
        link,
        &kOriginalLinkRangeKey,
        SystemFPSValuesFromRange(range),
        OBJC_ASSOCIATION_RETAIN_NONATOMIC
    );

    objc_setAssociatedObject(
        link,
        &kOriginalLinkFPSKey,
        nil,
        OBJC_ASSOCIATION_RETAIN_NONATOMIC
    );
}

static void SystemFPSCaptureOriginalLink(
    CADisplayLink *link
) {
    if (!link) return;

    id savedRange =
        objc_getAssociatedObject(link, &kOriginalLinkRangeKey);

    id savedFPS =
        objc_getAssociatedObject(link, &kOriginalLinkFPSKey);

    if (savedRange || savedFPS) {
        return;
    }

    if (@available(iOS 15.0, *)) {
        if ([link respondsToSelector:
             @selector(setPreferredFrameRateRange:)]) {

            SystemFPSStoreOriginalLinkRange(
                link,
                link.preferredFrameRateRange
            );

            return;
        }
    }

    SystemFPSStoreOriginalLinkFPS(
        link,
        link.preferredFramesPerSecond
    );
}

#pragma mark - Apply CADisplayLink

static void SystemFPSSetLinkRange(
    CADisplayLink *link,
    CAFrameRateRange range
) {
    if (@available(iOS 15.0, *)) {
        gApplyingLinkFPS = YES;

        @try {
            link.preferredFrameRateRange = range;
        }
        @finally {
            gApplyingLinkFPS = NO;
        }
    }
}

static void SystemFPSSetLinkFPS(
    CADisplayLink *link,
    NSInteger fps
) {
    gApplyingLinkFPS = YES;

    @try {
        link.preferredFramesPerSecond = fps;
    }
    @finally {
        gApplyingLinkFPS = NO;
    }
}

static void SystemFPSApplyToLink(CADisplayLink *link) {
    if (!link) return;

    SystemFPSCaptureOriginalLink(link);

    NSArray *savedRange =
        objc_getAssociatedObject(link, &kOriginalLinkRangeKey);

    NSNumber *savedFPS =
        objc_getAssociatedObject(link, &kOriginalLinkFPSKey);

    if (savedRange) {
        CAFrameRateRange original;

        if (SystemFPSRangeFromValues(savedRange, &original)) {

            CAFrameRateRange result = original;

            if (gSystemFPSEnabled) {
                result = SystemFPSLimitRange(original);
            }

            SystemFPSSetLinkRange(link, result);
            return;
        }
    }

    if (savedFPS) {
        NSInteger original = savedFPS.integerValue;
        NSInteger result = original;

        if (gSystemFPSEnabled) {
            if (result <= 0 || result > gTargetFPS) {
                result = gTargetFPS;
            }
        }

        SystemFPSSetLinkFPS(link, result);
    }
}

#pragma mark - Original CAAnimation values

static void SystemFPSStoreOriginalAnimationRange(
    CAAnimation *animation,
    CAFrameRateRange range
) {
    objc_setAssociatedObject(
        animation,
        &kOriginalAnimationRangeKey,
        SystemFPSValuesFromRange(range),
        OBJC_ASSOCIATION_RETAIN_NONATOMIC
    );
}

#pragma mark - Animation range

static void SystemFPSSetAnimationRange(
    CAAnimation *animation,
    CAFrameRateRange range
) {
    if (!animation) return;

    if (@available(iOS 15.0, *)) {
        gApplyingAnimationFPS = YES;

        @try {
            animation.preferredFrameRateRange = range;
        }
        @finally {
            gApplyingAnimationFPS = NO;
        }
    }
}

#pragma mark - Apply Core Animation

static void SystemFPSApplyAnimationTree(
    CAAnimation *animation,
    NSUInteger depth
) {
    if (!animation || depth > 8) {
        return;
    }

    SystemFPSRegisterAnimation(animation);

    if (@available(iOS 15.0, *)) {

        NSArray *savedRange =
            objc_getAssociatedObject(
                animation,
                &kOriginalAnimationRangeKey
            );

        if (!savedRange) {
            SystemFPSStoreOriginalAnimationRange(
                animation,
                animation.preferredFrameRateRange
            );

            savedRange =
                objc_getAssociatedObject(
                    animation,
                    &kOriginalAnimationRangeKey
                );
        }

        CAFrameRateRange original;

        if (SystemFPSRangeFromValues(savedRange, &original)) {

            CAFrameRateRange result = original;

            if (gSystemFPSEnabled) {
                result = SystemFPSLimitRange(original);
            }

            SystemFPSSetAnimationRange(animation, result);
        }
    }

    if ([animation isKindOfClass:CAAnimationGroup.class]) {

        CAAnimationGroup *group =
            (CAAnimationGroup *)animation;

        NSArray<CAAnimation *> *children =
            group.animations;

        for (CAAnimation *child in children) {
            SystemFPSApplyAnimationTree(
                child,
                depth + 1
            );
        }
    }
}

#pragma mark - Preserve animation settings when copied

static void SystemFPSPropagateAnimationOriginals(
    CAAnimation *source,
    CAAnimation *destination,
    NSUInteger depth
) {
    if (!source || !destination || depth > 8) {
        return;
    }

    NSArray *savedRange =
        objc_getAssociatedObject(
            source,
            &kOriginalAnimationRangeKey
        );

    if (savedRange) {
        objc_setAssociatedObject(
            destination,
            &kOriginalAnimationRangeKey,
            [savedRange copy],
            OBJC_ASSOCIATION_RETAIN_NONATOMIC
        );

        SystemFPSRegisterAnimation(destination);
    }

    if ([source isKindOfClass:CAAnimationGroup.class] &&
        [destination isKindOfClass:CAAnimationGroup.class]) {

        NSArray *sourceChildren =
            ((CAAnimationGroup *)source).animations;

        NSArray *destinationChildren =
            ((CAAnimationGroup *)destination).animations;

        NSUInteger count =
            MIN(sourceChildren.count, destinationChildren.count);

        for (NSUInteger i = 0; i < count; i++) {
            SystemFPSPropagateAnimationOriginals(
                sourceChildren[i],
                destinationChildren[i],
                depth + 1
            );
        }
    }
}

#pragma mark - Refresh all objects

static void SystemFPSRefreshAllLinks(void) {
    SystemFPSInitRegistry();

    NSArray<CADisplayLink *> *links;

    @synchronized (gDisplayLinks) {
        links = gDisplayLinks.allObjects;
    }

    for (CADisplayLink *link in links) {
        SystemFPSApplyToLink(link);
    }
}

static void SystemFPSRefreshAllAnimations(void) {
    SystemFPSInitRegistry();

    NSArray<CAAnimation *> *animations;

    @synchronized (gAnimations) {
        animations = gAnimations.allObjects;
    }

    for (CAAnimation *animation in animations) {
        SystemFPSApplyAnimationTree(animation, 0);
    }
}

static void SystemFPSRefreshAll(void) {
    SystemFPSLoadSettings();

    SystemFPSRefreshAllLinks();
    SystemFPSRefreshAllAnimations();

    SystemFPSInitRegistry();

    NSUInteger linkCount;
    NSUInteger animationCount;

    @synchronized (gDisplayLinks) {
        linkCount = gDisplayLinks.allObjects.count;
    }

    @synchronized (gAnimations) {
        animationCount = gAnimations.allObjects.count;
    }

    NSLog(
        @"[SystemFPS] REFRESH | %@ | FPS:%ld | PID:%d | Bundle:%@ | Links:%lu | Animations:%lu",
        gSystemFPSEnabled ? @"ON" : @"OFF",
        (long)gTargetFPS,
        getpid(),
        SystemFPSCurrentBundleID(),
        (unsigned long)linkCount,
        (unsigned long)animationCount
    );
}

#pragma mark - Darwin notification

static void SystemFPSReloadCallback(
    CFNotificationCenterRef center,
    void *observer,
    CFStringRef name,
    const void *object,
    CFDictionaryRef userInfo
) {
    SystemFPSRefreshAll();
}

#pragma mark - CADisplayLink hooks

%hook CADisplayLink

+ (CADisplayLink *)displayLinkWithTarget:(id)target
                                selector:(SEL)selector {

    CADisplayLink *link =
        %orig(target, selector);

    if (link) {
        SystemFPSRegisterLink(link);
        SystemFPSApplyToLink(link);
    }

    return link;
}

- (void)setPreferredFramesPerSecond:(NSInteger)framesPerSecond {

    if (!gApplyingLinkFPS) {
        SystemFPSStoreOriginalLinkFPS(
            self,
            framesPerSecond
        );
    }

    NSInteger result = framesPerSecond;

    if (gSystemFPSEnabled && !gApplyingLinkFPS) {
        if (result <= 0 || result > gTargetFPS) {
            result = gTargetFPS;
        }
    }

    %orig(result);
}

- (void)setPreferredFrameRateRange:(CAFrameRateRange)range {

    if (!gApplyingLinkFPS) {
        SystemFPSStoreOriginalLinkRange(
            self,
            range
        );
    }

    if (gSystemFPSEnabled && !gApplyingLinkFPS) {
        %orig(SystemFPSLimitRange(range));
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

#pragma mark - CAAnimation hooks

%hook CAAnimation

- (void)setPreferredFrameRateRange:(CAFrameRateRange)range {

    if (!gApplyingAnimationFPS) {
        SystemFPSStoreOriginalAnimationRange(
            self,
            range
        );

        SystemFPSRegisterAnimation(self);
    }

    if (gSystemFPSEnabled && !gApplyingAnimationFPS) {
        %orig(SystemFPSLimitRange(range));
    } else {
        %orig(range);
    }
}

- (id)copyWithZone:(NSZone *)zone {

    CAAnimation *copy = %orig;

    if (copy && copy != self) {
        SystemFPSPropagateAnimationOriginals(
            self,
            copy,
            0
        );
    }

    return copy;
}

%end

#pragma mark - CALayer hooks

%hook CALayer

- (void)addAnimation:(CAAnimation *)animation
              forKey:(NSString *)key {

    if (animation) {
        SystemFPSApplyAnimationTree(animation, 0);
    }

    %orig(animation, key);
}

%end

#pragma mark - Constructor

%ctor {
    @autoreleasepool {

        // Initialize every Logos hook.
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
            @"[SystemFPS] INITIALIZED | %@ | FPS:%ld | PID:%d | Bundle:%@",
            gSystemFPSEnabled ? @"ON" : @"OFF",
            (long)gTargetFPS,
            getpid(),
            SystemFPSCurrentBundleID()
        );
    }
}
