// WXKBCommon.m — 偏好面板公共基类与读写工具
#import "WXKBCommon.h"

static NSUserDefaults *WXKBDefaults(void) {
    static NSUserDefaults *d = nil;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        d = [[NSUserDefaults alloc] initWithSuiteName:WXKB_PREFS_DOMAIN];
    });
    return d;
}

id WXKBGetPref(NSString *key) {
    if (!key.length) {
        return nil;
    }
    return [WXKBDefaults() objectForKey:key];
}

void WXKBSetPref(NSString *key, id value) {
    if (!key.length) {
        return;
    }
    if (value == nil) {
        [WXKBDefaults() removeObjectForKey:key];
    } else {
        [WXKBDefaults() setObject:value forKey:key];
    }
    [WXKBDefaults() synchronize];
}

NSArray<NSString *> *WXKBColorPresets(void) {
    static NSArray *presets = nil;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        presets = @[
            @"#000000", @"#1C1C1E", @"#3A3A3C", @"#8E8E93", @"#C7C7CC", @"#FFFFFF",
            @"#FF3B30", @"#FF9500", @"#FFCC00", @"#34C759", @"#00C7BE", @"#30B0C7",
            @"#007AFF", @"#5856D6", @"#AF52DE", @"#FF2D55", @"#A2845E", @"#5AC8FA"
        ];
    });
    return presets;
}

@implementation WXKBBaseListController

+ (void)wxkbNotifyChanged {
    // 通知键盘扩展立刻重读偏好；收不到也没关系，重弹键盘一样生效。
    CFNotificationCenterPostNotification(
        CFNotificationCenterGetDarwinNotifyCenter(),
        CFSTR(WXKB_CHANGED_NOTIFICATION_C), NULL, NULL, YES);
}

#pragma mark - 统一走我们自己的偏好域

- (id)readPreferenceValue:(PSSpecifier *)specifier {
    NSString *key = [specifier propertyForKey:@"key"];
    id v = WXKBGetPref(key);
    if (v != nil) {
        return v;
    }
    return [specifier propertyForKey:@"default"];
}

- (void)setPreferenceValue:(id)value specifier:(PSSpecifier *)specifier {
    NSString *key = [specifier propertyForKey:@"key"];
    if (!key.length) {
        return;
    }
    WXKBSetPref(key, value);
    [[self class] wxkbNotifyChanged];
}

#pragma mark - Specifier 构造

- (PSSpecifier *)wxkbSwitch:(NSString *)name key:(NSString *)key def:(BOOL)def {
    PSSpecifier *sp = [PSSpecifier preferenceSpecifierNamed:name
                                                     target:self
                                                        set:@selector(setPreferenceValue:specifier:)
                                                        get:@selector(readPreferenceValue:)
                                                     detail:nil
                                                       cell:PSSwitchCellType
                                                       edit:nil];
    [sp setProperty:key forKey:@"key"];
    [sp setProperty:@(def) forKey:@"default"];
    return sp;
}

- (PSSpecifier *)wxkbLink:(NSString *)name detailClass:(NSString *)cls {
    Class c = NSClassFromString(cls);
    PSSpecifier *sp = [PSSpecifier preferenceSpecifierNamed:name
                                                     target:self
                                                        set:nil
                                                        get:nil
                                                     detail:c
                                                       cell:PSLinkCell
                                                       edit:nil];
    return sp;
}

- (PSSpecifier *)wxkbChoice:(NSString *)name key:(NSString *)key def:(id)def
                     values:(NSArray *)values titles:(NSArray *)titles {
    Class c = NSClassFromString(@"WXKBChoiceListController");
    PSSpecifier *sp = [PSSpecifier preferenceSpecifierNamed:name
                                                     target:self
                                                        set:@selector(setPreferenceValue:specifier:)
                                                        get:@selector(readPreferenceValue:)
                                                     detail:c
                                                       cell:PSLinkListCell
                                                       edit:nil];
    [sp setProperty:key forKey:@"key"];
    [sp setProperty:def forKey:@"default"];
    [sp setProperty:values forKey:@"values"];
    [sp setProperty:titles forKey:@"titles"];
    return sp;
}

- (PSSpecifier *)wxkbColor:(NSString *)name key:(NSString *)key def:(NSString *)def {
    Class c = NSClassFromString(@"WXKBColorListController");
    PSSpecifier *sp = [PSSpecifier preferenceSpecifierNamed:name
                                                     target:self
                                                        set:@selector(setPreferenceValue:specifier:)
                                                        get:@selector(readPreferenceValue:)
                                                     detail:c
                                                       cell:PSLinkCell
                                                       edit:nil];
    [sp setProperty:key forKey:@"key"];
    [sp setProperty:def forKey:@"default"];
    return sp;
}

- (PSSpecifier *)wxkbEdit:(NSString *)name key:(NSString *)key def:(NSString *)def
              placeholder:(NSString *)placeholder {
    PSSpecifier *sp = [PSSpecifier preferenceSpecifierNamed:name
                                                     target:self
                                                        set:@selector(setPreferenceValue:specifier:)
                                                        get:@selector(readPreferenceValue:)
                                                     detail:nil
                                                       cell:PSEditTextCell
                                                       edit:nil];
    [sp setProperty:key forKey:@"key"];
    [sp setProperty:def forKey:@"default"];
    [sp setProperty:placeholder forKey:@"placeholder"];
    return sp;
}

- (PSSpecifier *)wxkbSlider:(NSString *)name key:(NSString *)key def:(double)def
                        min:(double)min max:(double)max {
    PSSpecifier *sp = [PSSpecifier preferenceSpecifierNamed:name
                                                     target:self
                                                        set:@selector(setPreferenceValue:specifier:)
                                                        get:@selector(readPreferenceValue:)
                                                     detail:nil
                                                       cell:PSSliderCell
                                                       edit:nil];
    [sp setProperty:key forKey:@"key"];
    [sp setProperty:@(def) forKey:@"default"];
    [sp setProperty:@(min) forKey:@"min"];
    [sp setProperty:@(max) forKey:@"max"];
    return sp;
}

@end