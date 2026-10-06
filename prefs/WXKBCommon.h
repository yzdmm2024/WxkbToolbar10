// WXKBCommon.h — 偏好面板公共基类与读写工具
#import <Preferences/PSListController.h>
#import <Preferences/PSSpecifier.h>
#import <UIKit/UIKit.h>
#import "../src/WXKBShared.h"

id  WXKBGetPref(NSString *key);
void WXKBSetPref(NSString *key, id value);

NSArray<NSString *> *WXKBColorPresets(void);

@interface WXKBBaseListController : PSListController
+ (void)wxkbNotifyChanged;
- (PSSpecifier *)wxkbSwitch:(NSString *)name key:(NSString *)key def:(BOOL)def;
- (PSSpecifier *)wxkbLink:(NSString *)name detailClass:(NSString *)cls;
- (PSSpecifier *)wxkbChoice:(NSString *)name key:(NSString *)key def:(id)def
                     values:(NSArray *)values titles:(NSArray *)titles;
- (PSSpecifier *)wxkbColor:(NSString *)name key:(NSString *)key def:(NSString *)def;
- (PSSpecifier *)wxkbEdit:(NSString *)name key:(NSString *)key def:(NSString *)def
              placeholder:(NSString *)placeholder;
- (PSSpecifier *)wxkbSlider:(NSString *)name key:(NSString *)key def:(double)def
                        min:(double)min max:(double)max;
@end