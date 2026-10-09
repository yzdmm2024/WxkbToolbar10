// WXKBInlineGridCell.h — 内联网格 cell：把「单选 / 主题色板 / 26 字母键盘」直接画在设置里
#import <Preferences/PSTableCell.h>
#import "WXKBCommon.h"

@interface WXKBInlineGridCell : PSTableCell
- (void)wxkbRefreshLetterColors;
- (void)setWxkbEnabled:(BOOL)enabled;   // 未授权时整格置灰、按钮不可点
@end
