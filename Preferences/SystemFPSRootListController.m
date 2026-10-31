
#import "SystemFPSRootListController.h"
#import <CoreFoundation/CoreFoundation.h>
#import <Preferences/PSSpecifier.h>

static CFStringRef const kNotification =
    CFSTR("com.systemfps.preferences/reload");

static BOOL IsValidFPS(id value) {
    if (![value respondsToSelector:@selector(integerValue)])
        return NO;

    NSString *string = [value description];

    NSCharacterSet *digits =
        [NSCharacterSet decimalDigitCharacterSet];

    if (string.length == 0 ||
        [string rangeOfCharacterFromSet:
            digits.invertedSet].location != NSNotFound) {
        return NO;
    }

    NSInteger fps = [value integerValue];

    return fps >= 25 && fps <= 60;
}

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

    if ([specifier.properties[@"key"]
         isEqualToString:@"TargetFPS"]) {

        if (!IsValidFPS(value)) {
            UIAlertController *alert =
            [UIAlertController
                alertControllerWithTitle:@"FPS không hợp lệ"
                message:@"Vui lòng nhập số nguyên từ 25 đến 60."
                preferredStyle:UIAlertControllerStyleAlert];

            [alert addAction:
                [UIAlertAction
                    actionWithTitle:@"Đồng ý"
                    style:UIAlertActionStyleDefault
                    handler:nil]];

            [self presentViewController:alert
                               animated:YES
                             completion:nil];

            return;
        }

        value = @([value integerValue]);
    }

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
