#import "SystemFPSRootListController.h"
#import <Preferences/PSSpecifier.h>
#import <CoreFoundation/CoreFoundation.h>
#import <objc/message.h>

static CFStringRef const kDomain =
    CFSTR("com.systemfps.preferences");

static CFStringRef const kNotification =
    CFSTR("com.systemfps.preferences/reload");

static NSString * const kEnabledKey = @"EnabledBundleIDs";
static NSString * const kSpringBoardID = @"com.apple.springboard";

@interface SystemFPSRootListController () <
    UISearchResultsUpdating
>

@property (nonatomic, strong) UISearchController *searchController;
@property (nonatomic, copy) NSString *searchText;

@end

@implementation SystemFPSRootListController

#pragma mark - Search

- (void)viewDidLoad {
    [super viewDidLoad];

    self.searchController =
        [[UISearchController alloc]
            initWithSearchResultsController:nil];

    self.searchController.searchResultsUpdater = self;
    self.searchController.obscuresBackgroundDuringPresentation = NO;
    self.searchController.searchBar.placeholder =
        @"Tìm tên ứng dụng hoặc Bundle ID";

    self.navigationItem.searchController =
        self.searchController;

    self.navigationItem.hidesSearchBarWhenScrolling = NO;

    self.definesPresentationContext = YES;
}

- (void)updateSearchResultsForSearchController:
    (UISearchController *)searchController {

    self.searchText =
        searchController.searchBar.text ?: @"";

    _specifiers = nil;
    [self reloadSpecifiers];
}

#pragma mark - Preferences

- (NSArray *)enabledBundleIDs {
    CFPropertyListRef value =
        CFPreferencesCopyAppValue(
            (__bridge CFStringRef)kEnabledKey,
            kDomain
        );

    if (!value) {
        return @[kSpringBoardID];
    }

    NSArray *result = nil;

    if (CFGetTypeID(value) == CFArrayGetTypeID()) {
        result = [(__bridge NSArray *)value copy];
    }

    CFRelease(value);

    return result ?: @[kSpringBoardID];
}

- (void)saveEnabledBundleIDs:(NSArray *)bundleIDs {
    CFPreferencesSetAppValue(
        (__bridge CFStringRef)kEnabledKey,
        (__bridge CFPropertyListRef)bundleIDs,
        kDomain
    );

    CFPreferencesAppSynchronize(kDomain);

    CFNotificationCenterPostNotification(
        CFNotificationCenterGetDarwinNotifyCenter(),
        kNotification,
        NULL,
        NULL,
        true
    );
}

#pragma mark - Installed applications

- (NSArray *)installedApplications {
    Class workspaceClass =
        NSClassFromString(@"LSApplicationWorkspace");

    if (!workspaceClass) {
        return @[];
    }

    SEL defaultSelector =
        NSSelectorFromString(@"defaultWorkspace");

    SEL applicationsSelector =
        NSSelectorFromString(@"allInstalledApplications");

    if (![workspaceClass respondsToSelector:defaultSelector]) {
        return @[];
    }

    id (*sendClass)(id, SEL) =
        (id (*)(id, SEL))objc_msgSend;

    id workspace =
        sendClass(workspaceClass, defaultSelector);

    if (![workspace respondsToSelector:applicationsSelector]) {
        return @[];
    }

    id (*sendObject)(id, SEL) =
        (id (*)(id, SEL))objc_msgSend;

    NSArray *proxies =
        sendObject(workspace, applicationsSelector);

    NSMutableArray *applications =
        [NSMutableArray array];

    NSString *query =
        [self.searchText stringByTrimmingCharactersInSet:
            NSCharacterSet.whitespaceAndNewlineCharacterSet];

    for (id proxy in proxies) {
        NSString *bundleID = nil;
        NSString *displayName = nil;
        BOOL isSystem = NO;

        @try {
            bundleID =
                [proxy valueForKey:@"applicationIdentifier"];

            displayName =
                [proxy valueForKey:@"localizedName"];

            id systemValue =
                [proxy valueForKey:@"isSystemApplication"];

            if ([systemValue respondsToSelector:@selector(boolValue)]) {
                isSystem = [systemValue boolValue];
            }
        }
        @catch (__unused NSException *exception) {
            continue;
        }

        if (![bundleID isKindOfClass:NSString.class] ||
            bundleID.length == 0) {
            continue;
        }

        if (![displayName isKindOfClass:NSString.class] ||
            displayName.length == 0) {
            displayName = bundleID;
        }

        if ([bundleID isEqualToString:kSpringBoardID]) {
            continue;
        }

        // Bổ sung nhận diện dự phòng cho ứng dụng Apple.
        if ([bundleID hasPrefix:@"com.apple."]) {
            isSystem = YES;
        }

        if (query.length > 0) {
            BOOL nameMatches =
                [displayName rangeOfString:query
                    options:NSCaseInsensitiveSearch].location
                    != NSNotFound;

            BOOL bundleMatches =
                [bundleID rangeOfString:query
                    options:NSCaseInsensitiveSearch].location
                    != NSNotFound;

            if (!nameMatches && !bundleMatches) {
                continue;
            }
        }

        [applications addObject:@{
            @"name": displayName,
            @"bundleID": bundleID,
            @"isSystem": @(isSystem)
        }];
    }

    [applications sortUsingComparator:
        ^NSComparisonResult(NSDictionary *a, NSDictionary *b) {

        return [a[@"name"]
            localizedCaseInsensitiveCompare:b[@"name"]];
    }];

    return applications;
}

#pragma mark - Specifier helpers

- (PSSpecifier *)makeGroup:(NSString *)name {
    return [PSSpecifier preferenceSpecifierNamed:name
        target:nil
        set:nil
        get:nil
        detail:nil
        cell:PSGroupCell
        edit:nil];
}

- (PSSpecifier *)makeSwitch:(NSString *)name
                   bundleID:(NSString *)bundleID {

    PSSpecifier *specifier =
        [PSSpecifier preferenceSpecifierNamed:name
            target:self
            set:@selector(setAppEnabled:specifier:)
            get:@selector(readAppEnabled:)
            detail:nil
            cell:PSSwitchCell
            edit:nil];

    [specifier setProperty:bundleID forKey:@"bundleID"];

    return specifier;
}

#pragma mark - Specifiers

- (NSArray *)specifiers {
    if (!_specifiers) {
        NSMutableArray *items =
            [[self loadSpecifiersFromPlistName:@"Root"
                                        target:self] mutableCopy];

        NSArray *applications =
            [self installedApplications];

        NSMutableArray *systemApps =
            [NSMutableArray array];

        NSMutableArray *userApps =
            [NSMutableArray array];

        for (NSDictionary *app in applications) {
            if ([app[@"isSystem"] boolValue]) {
                [systemApps addObject:app];
            } else {
                [userApps addObject:app];
            }
        }

        // SpringBoard riêng
        [items addObject:
            [self makeGroup:@"ĐIỀU KHIỂN HỆ THỐNG"]];

        [items addObject:
            [self makeSwitch:@"SpringBoard"
                    bundleID:kSpringBoardID]];

        // System applications
        [items addObject:
            [self makeGroup:@"ỨNG DỤNG HỆ THỐNG"]];

        for (NSDictionary *app in systemApps) {
            [items addObject:
                [self makeSwitch:app[@"name"]
                        bundleID:app[@"bundleID"]]];
        }

        // User applications
        [items addObject:
            [self makeGroup:@"ỨNG DỤNG ĐÃ CÀI"]];

        for (NSDictionary *app in userApps) {
            [items addObject:
                [self makeSwitch:app[@"name"]
                        bundleID:app[@"bundleID"]]];
        }

        if (systemApps.count == 0 && userApps.count == 0) {
            [items addObject:
                [self makeGroup:@"Không tìm thấy ứng dụng"]];
        }

        _specifiers = items;
    }

    return _specifiers;
}

#pragma mark - Switch

- (id)readAppEnabled:(PSSpecifier *)specifier {
    NSString *bundleID =
        [specifier propertyForKey:@"bundleID"];

    return @([[self enabledBundleIDs]
        containsObject:bundleID ?: @""]);
}

- (void)setAppEnabled:(id)value
            specifier:(PSSpecifier *)specifier {

    NSString *bundleID =
        [specifier propertyForKey:@"bundleID"];

    if (bundleID.length == 0) {
        return;
    }

    NSMutableArray *enabled =
        [[self enabledBundleIDs] mutableCopy];

    if ([value boolValue]) {
        if (![enabled containsObject:bundleID]) {
            [enabled addObject:bundleID];
        }
    } else {
        [enabled removeObject:bundleID];
    }

    [self saveEnabledBundleIDs:enabled];
}

#pragma mark - FPS input

- (void)setPreferenceValue:(id)value
                specifier:(PSSpecifier *)specifier {

    NSString *key =
        [specifier propertyForKey:@"key"];

    if ([key isEqualToString:@"TargetFPS"]) {
        NSString *str = [value description];

        NSCharacterSet *invalid =
            [[NSCharacterSet decimalDigitCharacterSet] invertedSet];

        if (str.length == 0 ||
            [str rangeOfCharacterFromSet:invalid].location
                != NSNotFound) {
            return;
        }

        NSInteger fps = str.integerValue;

        if (fps < 25 || fps > 60) {
            UIAlertController *alert =
                [UIAlertController
                    alertControllerWithTitle:@"FPS không hợp lệ"
                    message:@"Vui lòng nhập số nguyên từ 25 đến 60."
                    preferredStyle:UIAlertControllerStyleAlert];

            [alert addAction:
                [UIAlertAction
                    actionWithTitle:@"Đóng"
                    style:UIAlertActionStyleDefault
                    handler:nil]];

            [self presentViewController:alert
                               animated:YES
                             completion:nil];

            return;
        }

        value = @(fps);
    }

    [super setPreferenceValue:value specifier:specifier];

    CFPreferencesAppSynchronize(kDomain);

    CFNotificationCenterPostNotification(
        CFNotificationCenterGetDarwinNotifyCenter(),
        kNotification,
        NULL,
        NULL,
        true
    );
}

#pragma mark - Reset

- (void)resetFPS {
    CFPreferencesSetAppValue(
        CFSTR("TargetFPS"),
        (__bridge CFPropertyListRef)@60,
        kDomain
    );

    CFPreferencesAppSynchronize(kDomain);

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
