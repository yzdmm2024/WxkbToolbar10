// WXKBPreviewKeyboardView.h — 设置面板里的「实时键盘预览」
//
// 完全独立于键盘扩展进程，在「设置」App 进程里用同一套取色 / 键帽渲染数学，
// 把当前偏好画成一台仿真 QWERTY 键盘。改任意控件 -> 发通知 -> 这里立刻重绘，
// 视觉与真机键盘 100% 同源（同一份 WXKBApplyCap 颜色推导公式）。
//
// 仅放 ASCII / 标准 API，避免 Windows 交叉编译链路出问题。
#import <UIKit/UIKit.h>
#import "WXKBCommon.h"

@interface WXKBPreviewKeyboardView : UIView

// 重新读取偏好并重绘（偏好变更后调用；本类也会自己监听 changed 通知）。
- (void)refresh;

// 根据宽度给出合适高度（键盘比例 390:260）。
+ (CGFloat)preferredHeightForWidth:(CGFloat)width;

@end
