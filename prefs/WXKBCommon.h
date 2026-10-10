// WXKBCommon.h — 偏好面板公共基类与读写工具
#import <Preferences/PSListController.h>
#import <Preferences/PSSpecifier.h>
#import <UIKit/UIKit.h>
#import "../src/WXKBShared.h"

id  WXKBGetPref(NSString *key);
void WXKBSetPref(NSString *key, id value);

NSArray<NSString *> *WXKBColorPresets(void);

// #RRGGBB / #RRGGBBAA <-> UIColor
UIColor *WXKBColorFromHex(NSString *hex);
NSString *WXKBHexFromColor(UIColor *color);

// 主题族色板（预览 / 面板共用，与 Tweak 的 kThemeFam 同源）：
// 0 = 百度彩虹（原图，不在渐变族里）；1..31 = 渐变族 {色相起, 色相止, 饱和, 亮度}
extern const double WXKBThemeFam[32][4];
UIColor *WXKBFromHSL(double h, double s, double l);
UIColor *WXKBThemeSwatchColor(NSInteger theme);

// 26 字母逐个配色的读写
NSString *WXKBLetterColor(NSInteger index);
void WXKBSetLetterColor(NSInteger index, NSString *hex);

@class WXKBValueSliderCell;

@interface WXKBBaseListController : PSListController <UIColorPickerViewControllerDelegate>

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
// 带数字显示 + 整数步进的滑块（右侧实时显示带正负号的值，滑动一步 = step）
- (PSSpecifier *)wxkbValueSlider:(NSString *)name key:(NSString *)key def:(double)def
                              min:(double)min max:(double)max step:(double)step;

// 点一下直接弹系统取色器（带色块预览）
- (PSSpecifier *)wxkbColorRow:(NSString *)name key:(NSString *)key def:(NSString *)def;
// 26 字母逐个配色行
- (PSSpecifier *)wxkbLetterRow:(NSString *)letter index:(NSInteger)index;
// 按钮行
- (PSSpecifier *)wxkbButton:(NSString *)name action:(SEL)action;

// 直接弹出系统取色器（不走二级页，消除 3 秒空白）；用于 26 字母逐个上色
@property (nonatomic, assign) NSInteger wxkbPendingLetterIndex;
@property (nonatomic, copy) NSString *wxkbPendingKey;
- (void)wxkbPresentColorForLetter:(NSInteger)idx title:(NSString *)title;

@end