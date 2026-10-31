
#import "SystemFPSRootListController.h"
#import <CoreFoundation/CoreFoundation.h>

static CFStringRef const kNotification =
    CFSTR("com.systemfps.preferences/reload");

@implementation SystemFPSRootListController

- (NSArray *)specifiers {
    if (!_specifiers) {
        _specifiers = [self
            loadSpecifiersFromPlistName:@"Root"
            target:self];
    }
    return _specifiers;
}

- (void)setPreferenceValue:(id)value
                specifier:(PSSpecifier *)specifier {

    [super setPreferenceValue:value
                    specifier:specifier];

    CFPreferencesAppSynchronize(
        CFSTR("com.systemfps.preferences")
    );

    CFNotificationCenterPostNotification(
        CFNotificationCenterGetDarwinNotifyCenter(),
        kNotification,
        NULL,
        NULL,
        true
    );
}

- (void)resetFPS {
    CFPreferencesSetAppValue(
        CFSTR("TargetFPS"),
        (__bridge CFPropertyListRef)@60,
        CFSTR("com.systemfps.preferences")
    );

    CFPreferencesAppSynchronize(
        CFSTR("com.systemfps.preferences")
    );

    CFNotificationCenterPostNotification(
        CFNotificationCenterGetDarwinNotifyCenter(),
        kNotification,
        NULL,
        NULL,
        true
    );

    [self reloadSpecifiers];
}

@end
