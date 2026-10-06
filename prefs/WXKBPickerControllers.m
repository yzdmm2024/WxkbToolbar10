// WXKBPickerControllers.m — 颜色选择器与单选列表
#import "WXKBCommon.h"

#pragma mark - 颜色选择

@interface WXKBColorListController : WXKBBaseListController
@end

@implementation WXKBColorListController

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = [self.specifier name] ?: @"选择颜色";
}

- (NSArray *)specifiers {
    if (_specifiers) {
        return _specifiers;
    }
    NSString *key = [self.specifier propertyForKey:@"key"];
    NSMutableArray *s = [NSMutableArray array];

    PSSpecifier *g = [PSSpecifier groupSpecifierWithName:@"自定义"];
    [g setProperty:@"填 #RRGGBB，例如 #1C1C1E。" forKey:@"footerText"];
    [s addObject:g];

    PSSpecifier *e = [PSSpecifier preferenceSpecifierNamed:@""
                                                    target:self
                                                       set:@selector(setPreferenceValue:specifier:)
                                                       get:@selector(readPreferenceValue:)
                                                    detail:nil
                                                      cell:PSEditTextCell
                                                      edit:nil];
    [e setProperty:key forKey:@"key"];
    [e setProperty:[self.specifier propertyForKey:@"default"] forKey:@"default"];
    [e setProperty:@"#RRGGBB" forKey:@"placeholder"];
    [s addObject:e];

    g = [PSSpecifier groupSpecifierWithName:@"预设"];
    [s addObject:g];
    for (NSString *hex in WXKBColorPresets()) {
        PSSpecifier *sp = [PSSpecifier preferenceSpecifierNamed:hex
                                                         target:self
                                                            set:nil
                                                            get:nil
                                                         detail:nil
                                                           cell:PSButtonCell
                                                           edit:nil];
        [sp setProperty:@selector(pickColor:) forKey:@"action"];
        [sp setProperty:hex forKey:@"hexValue"];
        [s addObject:sp];
    }

    _specifiers = s;
    return _specifiers;
}

- (void)pickColor:(PSSpecifier *)specifier {
    NSString *key = [self.specifier propertyForKey:@"key"];
    WXKBSetPref(key, [specifier propertyForKey:@"hexValue"]);
    [[self class] wxkbNotifyChanged];
    [self.navigationController popViewControllerAnimated:YES];
}

@end

#pragma mark - 单选列表

@interface WXKBChoiceListController : WXKBBaseListController
@end

@implementation WXKBChoiceListController

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = [self.specifier name] ?: @"选择";
}

- (NSArray *)specifiers {
    if (_specifiers) {
        return _specifiers;
    }
    NSArray *values = [self.specifier propertyForKey:@"values"];
    NSArray *titles = [self.specifier propertyForKey:@"titles"];
    id current = [self readPreferenceValue:self.specifier];

    NSMutableArray *s = [NSMutableArray array];
    [s addObject:[PSSpecifier groupSpecifierWithName:nil]];
    for (NSUInteger i = 0; i < values.count; i++) {
        BOOL selected = [[values[i] description] isEqualToString:[current description]];
        NSString *title = selected ? [@"✓ " stringByAppendingString:titles[i]] : titles[i];
        PSSpecifier *sp = [PSSpecifier preferenceSpecifierNamed:title
                                                         target:self
                                                            set:nil
                                                            get:nil
                                                         detail:nil
                                                           cell:PSButtonCell
                                                           edit:nil];
        [sp setProperty:@selector(choose:) forKey:@"action"];
        [sp setProperty:values[i] forKey:@"choiceValue"];
        [s addObject:sp];
    }
    _specifiers = s;
    return _specifiers;
}

- (void)choose:(PSSpecifier *)specifier {
    NSString *key = [self.specifier propertyForKey:@"key"];
    WXKBSetPref(key, [specifier propertyForKey:@"choiceValue"]);
    [[self class] wxkbNotifyChanged];
    [self.navigationController popViewControllerAnimated:YES];
}

@end