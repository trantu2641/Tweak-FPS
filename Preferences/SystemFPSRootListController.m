#import "SystemFPSRootListController.h"
#import <Preferences/PSSpecifier.h>
#import <CoreFoundation/CoreFoundation.h>
#import <objc/message.h>
#import <dlfcn.h>

static CFStringRef const kDomain =
    CFSTR("com.systemfps.preferences");

static CFStringRef const kNotification =
    CFSTR("com.systemfps.preferences/reload");

static NSString * const kEnabledKey = @"EnabledBundleIDs";
static NSString * const kSpringBoardID = @"com.apple.springboard";

@interface SystemFPSRootListController () <UISearchResultsUpdating>

@property (nonatomic, strong) UISearchController *searchController;
@property (nonatomic, copy) NSString *searchText;

@end

#pragma mark - Safe private API access

static id SystemFPSReadProperty(id object, NSString *key) {
    if (!object || key.length == 0) {
        return nil;
    }

    @try {
        return [object valueForKey:key];
    }
    @catch (__unused NSException *exception) {
        return nil;
    }
}

static NSString *SystemFPSStringProperty(id object, NSString *key) {
    id value = SystemFPSReadProperty(object, key);

    if ([value isKindOfClass:NSString.class] &&
        [(NSString *)value length] > 0) {
        return value;
    }

    return nil;
}

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

#pragma mark - Load LaunchServices

- (Class)applicationWorkspaceClass {
    static Class workspaceClass = Nil;
    static dispatch_once_t onceToken;

    dispatch_once(&onceToken, ^{
        dlopen(
            "/System/Library/Frameworks/MobileCoreServices.framework/MobileCoreServices",
            RTLD_NOW
        );

        dlopen(
            "/System/Library/PrivateFrameworks/MobileCoreServices.framework/MobileCoreServices",
            RTLD_NOW
        );

        workspaceClass =
            NSClassFromString(@"LSApplicationWorkspace");
    });

    return workspaceClass;
}

#pragma mark - Installed applications

- (NSArray *)installedApplications {
    Class workspaceClass = [self applicationWorkspaceClass];

    if (!workspaceClass) {
        NSLog(@"[SystemFPS] LSApplicationWorkspace unavailable");
        return @[];
    }

    SEL defaultSelector =
        NSSelectorFromString(@"defaultWorkspace");

    SEL applicationsSelector =
        NSSelectorFromString(@"allInstalledApplications");

    if (![workspaceClass respondsToSelector:defaultSelector]) {
        NSLog(@"[SystemFPS] defaultWorkspace unavailable");
        return @[];
    }

    id (*sendClass)(id, SEL) =
        (id (*)(id, SEL))objc_msgSend;

    id workspace =
        sendClass(workspaceClass, defaultSelector);

    if (!workspace ||
        ![workspace respondsToSelector:applicationsSelector]) {
        NSLog(@"[SystemFPS] allInstalledApplications unavailable");
        return @[];
    }

    id (*sendObject)(id, SEL) =
        (id (*)(id, SEL))objc_msgSend;

    id result =
        sendObject(workspace, applicationsSelector);

    if (![result isKindOfClass:NSArray.class]) {
        NSLog(@"[SystemFPS] Application result is not an array");
        return @[];
    }

    NSArray *proxies = (NSArray *)result;

    NSMutableArray *applications =
        [NSMutableArray array];

    NSString *query =
        [self.searchText stringByTrimmingCharactersInSet:
            NSCharacterSet.whitespaceAndNewlineCharacterSet];

    for (id proxy in proxies) {

        // Bundle ID: đọc từng thuộc tính riêng biệt.
        NSString *bundleID =
            SystemFPSStringProperty(proxy, @"bundleIdentifier");

        if (bundleID.length == 0) {
            bundleID =
                SystemFPSStringProperty(proxy, @"applicationIdentifier");
        }

        if (bundleID.length == 0) {
            continue;
        }

        // Tên ứng dụng.
        NSString *displayName =
            SystemFPSStringProperty(proxy, @"localizedName");

        if (displayName.length == 0) {
            displayName =
                SystemFPSStringProperty(proxy, @"localizedShortName");
        }

        if (displayName.length == 0) {
            displayName = bundleID;
        }

        if ([bundleID isEqualToString:kSpringBoardID]) {
            continue;
        }

        // Nhận diện ứng dụng hệ thống.
        BOOL isSystem = NO;

        id systemValue =
            SystemFPSReadProperty(proxy, @"isSystemApplication");

        if ([systemValue respondsToSelector:@selector(boolValue)]) {
            isSystem = [systemValue boolValue];
        }

        NSString *applicationType =
            SystemFPSStringProperty(proxy, @"applicationType");

        if ([applicationType caseInsensitiveCompare:@"System"]
            == NSOrderedSame) {
            isSystem = YES;
        }

        if ([applicationType caseInsensitiveCompare:@"User"]
            == NSOrderedSame) {
            isSystem = NO;
        }

        // Dự phòng cho các ứng dụng Apple.
        if ([bundleID hasPrefix:@"com.apple."]) {
            isSystem = YES;
        }

        // Tìm kiếm tên hoặc Bundle ID.
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

    NSLog(
        @"[SystemFPS] Found %lu applications",
        (unsigned long)applications.count
    );

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

        // SpringBoard.
        [items addObject:
            [self makeGroup:@"ĐIỀU KHIỂN HỆ THỐNG"]];

        [items addObject:
            [self makeSwitch:@"SpringBoard"
                    bundleID:kSpringBoardID]];

        // System applications.
        [items addObject:
            [self makeGroup:
                [NSString stringWithFormat:
                    @"ỨNG DỤNG HỆ THỐNG (%lu)",
                    (unsigned long)systemApps.count]]];

        for (NSDictionary *app in systemApps) {
            [items addObject:
                [self makeSwitch:app[@"name"]
                        bundleID:app[@"bundleID"]]];
        }

        // User applications.
        [items addObject:
            [self makeGroup:
                [NSString stringWithFormat:
                    @"ỨNG DỤNG ĐÃ CÀI (%lu)",
                    (unsigned long)userApps.count]]];

        for (NSDictionary *app in userApps) {
            [items addObject:
                [self makeSwitch:app[@"name"]
                        bundleID:app[@"bundleID"]]];
        }

        if (applications.count == 0) {
            [items addObject:
                [self makeGroup:
                    @"Không đọc được danh sách ứng dụng"]];

            NSLog(@"[SystemFPS] Application list is empty");
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
