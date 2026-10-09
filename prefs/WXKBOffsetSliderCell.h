// WXKBOffsetSliderCell.h — 键盘位置滑块 cell
//
// 整数步进（滑动一次≈1pt）、带正负数值显示的 UISlider，直接写 WXKB_KEY_OFFSET。
// 滑动时实时通知预览（wxkbNotifyChanged），让设置顶部的仿真键盘跟着上下移动。
// 仿 WXKBInlineGridCell 的 cellClass 注入方式挂载到 PSSpecifier。
#import <Preferences/PSTableCell.h>
#import "WXKBCommon.h"

@interface WXKBOffsetSliderCell : PSTableCell
@end
