// WXKBThemeProfile.h — 我的主题（存档 / 切换 / 删除）
//
// 把当前整套视觉偏好快照成一个具名主题，存进同一个偏好 suite 里；
// 「应用」= 把该主题覆盖写回偏好并通知键盘扩展重读。跨进程走 NSUserDefaults，
// 设置里点一下，真机键盘立刻生效。
#import <Foundation/Foundation.h>
#import "WXKBCommon.h"

// 参与快照的偏好键（覆盖所有视觉维度）
NSArray<NSString *> *WXKBThemeProfileKeys(void);

// 所有已存主题名（按存档顺序）
NSArray<NSString *> *WXKBThemeProfileNames(void);

// 把当前偏好存为名为 name 的主题；name 为空或已存在则失败（已存在请用覆盖版）
BOOL WXKBSaveThemeProfile(NSString *name);

// 覆盖保存（同名直接更新）
BOOL WXKBOverwriteThemeProfile(NSString *name);

// 应用某个主题到当前偏好（写回 + 发 changed 通知）
BOOL WXKBApplyThemeProfile(NSString *name);

// 删除
BOOL WXKBDeleteThemeProfile(NSString *name);
