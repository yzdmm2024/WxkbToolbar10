// WXKBLetterColors.m — 26 字母逐个配色
#import "WXKBCommon.h"

@interface WXKBLetterColorController : WXKBBaseListController
@end

@implementation WXKBLetterColorController

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = @"26 字母配色";
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    _specifiers = nil;
    [self reloadSpecifiers];
}

- (NSArray *)specifiers {
    if (_specifiers) {
        return _specifiers;
    }
    NSMutableArray *s = [NSMutableArray array];
    PSSpecifier *g = [PSSpecifier groupSpecifierWithName:@"逐个字母"];
    [g setProperty:@"只给想改的字母单独上色即可；没设置的字母跟随「字母键底色」。"
            forKey:@"footerText"];
    [s addObject:g];

    for (NSInteger i = 0; i < 26; i++) {
        NSString *letter = [NSString stringWithFormat:@"%c", (char)('A' + i)];
        [s addObject:[self wxkbLetterRow:letter index:i]];
    }

    _specifiers = s;
    return _specifiers;
}

@end