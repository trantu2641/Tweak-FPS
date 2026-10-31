
#import "SystemFPSRootListController.h"
#import <Preferences/PSSpecifier.h>
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

    NSString *key = [specifier.properties objectForKey:@"key"];

    if ([key isEqualToString:@"TargetFPS"]) {
        NSString *str = [value description];

        NSCharacterSet *invalid =
        [[NSCharacterSet decimalDigitCharacterSet] invertedSet];

        if (str.length == 0 ||
            [str rangeOfCharacterFromSet:invalid].location != NSNotFound) {
            return;
        }

        NSInteger fps = [str integerValue];

        if (fps < 25 || fps > 60) {
            UIAlertController *alert =
            [UIAlertController alertControllerWithTitle:@"FPS không hợp lệ"
            message:@"Vui lòng nhập số nguyên từ 25 đến 60."
            preferredStyle:UIAlertControllerStyleAlert];

            [alert addAction:
                [UIAlertAction actionWithTitle:@"Đóng"
                style:UIAlertActionStyleDefault
                handler:nil]];

            [self presentViewController:alert
            animated:YES completion:nil];

            return;
        }

        value = @(fps);
    }

    [super setPreferenceValue:value specifier:specifier];

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
