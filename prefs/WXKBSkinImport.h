// WXKBSkinImport.h — 百度 .bdi 皮肤导入 / 内置预设 / 清除
// 仅在 Preferences 进程（设置面板）调用：有文件权限、可调 /usr/bin/unzip。
#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>

// 从系统文件选择器选 .bdi 并导入（解析出深色/浅色背景图 + 配色，写入偏好）。
void WXKBImportBdiFromViewController(UIViewController *vc);

// 应用内置「秋意」预设（从本 bundle 读 bj_dark/bj_light.png + 预设配色）。
BOOL WXKBApplyQiuyiPreset(void);

// 清除全部皮肤相关偏好，回到默认。
void WXKBClearSkin(void);
