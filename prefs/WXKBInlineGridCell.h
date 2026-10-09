// WXKBInlineGridCell.h — 内联网格 cell：把「单选 / 主题色板 / 26 字母键盘」直接画在设置里
#import <Preferences/PSTableCell.h>
#import "WXKBCommon.h"

@interface WXKBInlineGridCell : PSTableCell
- (void)wxkbRefreshLetterColors;
- (void)wxkbResetScroll;   // 回到前台时复位内嵌 scrollView 手势（防切后台回来卡死）
- (void)setWxkbEnabled:(BOOL)enabled;   // 未授权时整格置灰、按钮不可点（滚动仍可看）
@end
