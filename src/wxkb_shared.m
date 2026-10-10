/* ============================================================
 * wxkb_shared.m —— WxkbToolbar10 跨进程共享存储（设置面板 ↔ 键盘扩展）
 *
 * 两套进程通过 cfprefsd 共享域 com.tencent.wetype.keyboard 互通偏好。
 * 此文件额外提供「容器 plist 直写直读」双通道兜底，保证设置改动可靠送达
 * 沙盒内的键盘扩展（cfprefsd 跨进程视图未同步时的兜底）。
 *
 * 注意：本文件不含任何授权 / 验证逻辑，纯粹是偏好同步工具。
 * ============================================================ */
#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <CoreFoundation/CoreFoundation.h>

// 共享域 = 微信键盘扩展自己的 bundle id。键盘扩展沙盒内读不到真实
// /var/mobile/Library/Preferences，但能经 cfprefsd 读写自己的域；设置面板
// （未沙盒）可写任意域，故两端走同一域即可互通。
static NSString *__domain(void) { return @"com.tencent.wetype.keyboard"; }

static NSString *__domainPlistName(void) {
    return [__domain() stringByAppendingString:@".plist"];
}

/* ---- 微信键盘（宿主 App）数据容器定位 ----
 * cfprefsd 对沙盒客户端只开放其「容器内」的域文件；设置面板经 CFPreferences
 * 写的是 /var/mobile/Library/Preferences/<domain>.plist，键盘扩展的 cfprefsd
 * 视图未必命中同一份文件。把关键键值再合并直写一份到 WeType 容器的
 * <...>/Library/Preferences/<domain>.plist，键盘侧（沙盒至少能读自己容器）
 * 直读该文件即可拿到。沙盒进程扫描不了 /var/mobile/Containers，扫描失败
 * 自然得到空列表，写端自动退化为 no-op，读端则用 NSHomeDirectory 定位。 */
static NSArray<NSString *> *_wetypeContainerPrefsDirs(void) {
    static NSArray *dirs = nil;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        NSFileManager *fm = [NSFileManager defaultManager];
        NSString *root = @"/var/mobile/Containers/Data/Application";
        NSArray *ids = [fm contentsOfDirectoryAtPath:root error:nil];
        if (!ids.count) return;   // 沙盒进程：扫描被拒 → 空
        NSMutableArray *out = [NSMutableArray array];
        for (NSString *cid in ids) {
            NSString *dir = [root stringByAppendingPathComponent:cid];
            NSDictionary *meta = [NSDictionary dictionaryWithContentsOfFile:
                [dir stringByAppendingPathComponent:
                     @".com.apple.mobile_container_manager.metadata.plist"]];
            NSString *ident = meta[@"MCMMetadataIdentifier"];
            if (![ident isKindOfClass:[NSString class]]) continue;
            /* 覆盖 WeType App 本体与键盘扩展各自的容器 */
            if (![ident hasPrefix:@"com.tencent.wetype"]) continue;
            NSString *pd = [dir stringByAppendingPathComponent:@"Library/Preferences"];
            if ([fm fileExistsAtPath:pd]) [out addObject:pd];
        }
        dirs = out;
    });
    return dirs;
}

/* 任意进程：自己容器里的共享域 plist 全路径（读端用） */
static NSString *_wxkbHomePrefFile(void) {
    NSString *home = NSHomeDirectory();
    if (!home.length) return nil;
    return [home stringByAppendingPathComponent:
            [@"Library/Preferences/" stringByAppendingString:__domainPlistName()]];
}

/* 设置侧直写：把 key/value 合并写进 WeType 容器的域 plist（value=nil 删除键）。
 * 只在未沙盒进程里真正生效；键盘侧调用是 no-op（扫描不到容器）。 */
void wxkb_shared_sync(NSString *key, id value) {
    if (!key.length) return;
    for (NSString *dir in _wetypeContainerPrefsDirs()) {
        NSString *path = [dir stringByAppendingPathComponent:__domainPlistName()];
        NSMutableDictionary *d = [[NSMutableDictionary alloc]
                                  initWithContentsOfFile:path];
        if (![d isKindOfClass:[NSMutableDictionary class]]) {
            d = [NSMutableDictionary dictionary];
        }
        if (value) d[key] = value;
        else       [d removeObjectForKey:key];
        if (!d.count && ![NSFileManager.defaultManager fileExistsAtPath:path]) continue;
        NSData *data = [NSPropertyListSerialization
                        dataWithPropertyList:d
                        format:NSPropertyListBinaryFormat_v1_0
                        options:0 error:nil];
        if (data) [data writeToFile:path atomically:YES];
    }
}
