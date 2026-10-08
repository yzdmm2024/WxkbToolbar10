// WXKBThemeProfile.m — 我的主题（存档 / 切换 / 删除）
//
// 把当前整套视觉偏好快照成一个具名主题，存进同一个偏好 suite 里
// （themeProfiles = { 主题名 -> { 偏好键 -> 值 } }）。
// 「应用」= 把该主题覆盖写回偏好并通知键盘扩展重读。跨进程走 NSUserDefaults +
// Darwin 通知，设置里点一下，真机键盘立刻生效。
#import "WXKBThemeProfile.h"
#import "WXKBCommon.h"

#pragma mark - 参与快照的偏好键（覆盖所有视觉维度）

NSArray<NSString *> *WXKBThemeProfileKeys(void) {
    static NSArray *keys = nil;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        keys = @[
            WXKB_KEY_BG_ENABLED, WXKB_KEY_BG_MODE, WXKB_KEY_BG_COLOR,
            WXKB_KEY_BG_IMAGE, WXKB_KEY_BG_IMAGE_DATA, WXKB_KEY_BG_ALPHA,
            WXKB_KEY_TRANSPARENT,
            WXKB_KEY_KEY_ENABLED, WXKB_KEY_LETTER_BG, WXKB_KEY_DIGIT_BG,
            WXKB_KEY_FUNC_L_BG, WXKB_KEY_FUNC_R_BG, WXKB_KEY_SPACE_BG,
            WXKB_KEY_KEY_TEXT, WXKB_KEY_KEY_TEXT_DARK,
            WXKB_KEY_KEY_HIGHLIGHT, WXKB_KEY_KEY_HIGHLIGHT_DARK,
            WXKB_KEY_GRAD_ENABLED, WXKB_KEY_GRAD_FROM, WXKB_KEY_GRAD_TO,
            WXKB_KEY_LETTER_MAP,
            WXKB_KEY_CORNER, WXKB_KEY_SHAPE,
            WXKB_KEY_SKIN_ENABLED, WXKB_KEY_SKIN_NAME, WXKB_KEY_SKIN_BG,
            WXKB_KEY_SKIN_THEME, WXKB_KEY_SKIN_DIR,
            WXKB_KEY_CAP_STYLE, WXKB_KEY_OFFSET
        ];
    });
    return keys;
}

#pragma mark - 内部读写

static NSMutableDictionary *WXKBProfilesStore(void) {
    id raw = WXKBGetPref(WXKB_KEY_THEME_PROFILES);
    NSMutableDictionary *d = [NSMutableDictionary dictionary];
    if ([raw isKindOfClass:[NSDictionary class]]) {
        [d addEntriesFromDictionary:raw];
    }
    return d;
}

NSArray<NSString *> *WXKBThemeProfileNames(void) {
    NSDictionary *d = WXKBGetPref(WXKB_KEY_THEME_PROFILES);
    if (![d isKindOfClass:[NSDictionary class]]) return @[];
    return [d.allKeys sortedArrayUsingSelector:@selector(localizedCaseInsensitiveCompare:)];
}

static BOOL WXKBSaveThemeProfileInternal(NSString *name, BOOL overwrite) {
    if (![name isKindOfClass:[NSString class]]) return NO;
    name = [name stringByTrimmingCharactersInSet:
                [NSCharacterSet whitespaceAndNewlineCharacterSet]];
    if (name.length == 0) return NO;

    NSMutableDictionary *store = WXKBProfilesStore();
    if (!overwrite && store[name]) return NO;   // 已存在且不允许覆盖

    // 快照：只存当前有值的视觉键，缺失的键在应用时复位为默认。
    NSMutableDictionary *snap = [NSMutableDictionary dictionary];
    for (NSString *k in WXKBThemeProfileKeys()) {
        id v = WXKBGetPref(k);
        if (v != nil) snap[k] = v;
    }
    store[name] = snap;
    WXKBSetPref(WXKB_KEY_THEME_PROFILES, store);
    return YES;
}

BOOL WXKBSaveThemeProfile(NSString *name) {
    return WXKBSaveThemeProfileInternal(name, NO);
}

BOOL WXKBOverwriteThemeProfile(NSString *name) {
    return WXKBSaveThemeProfileInternal(name, YES);
}

BOOL WXKBApplyThemeProfile(NSString *name) {
    if (![name isKindOfClass:[NSString class]] || name.length == 0) return NO;
    NSDictionary *store = WXKBGetPref(WXKB_KEY_THEME_PROFILES);
    if (![store isKindOfClass:[NSDictionary class]]) return NO;
    NSDictionary *snap = store[name];
    if (![snap isKindOfClass:[NSDictionary class]]) return NO;

    // 忠实还原：把快照里的键写回，不在快照里的视觉键复位为「未设置」。
    for (NSString *k in WXKBThemeProfileKeys()) {
        if (snap[k] != nil) WXKBSetPref(k, snap[k]);
        else WXKBSetPref(k, nil);
    }
    [WXKBBaseListController wxkbNotifyChanged];
    return YES;
}

BOOL WXKBDeleteThemeProfile(NSString *name) {
    if (![name isKindOfClass:[NSString class]] || name.length == 0) return NO;
    NSMutableDictionary *store = WXKBProfilesStore();
    if (!store[name]) return NO;
    [store removeObjectForKey:name];
    WXKBSetPref(WXKB_KEY_THEME_PROFILES, store);
    return YES;
}
