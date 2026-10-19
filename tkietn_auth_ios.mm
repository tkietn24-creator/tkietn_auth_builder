/**
 * ============================================================================
 * 🍏 TKIETN-AUTH VIP iOS NATIVE SDK & HOOK ENGINE
 * ============================================================================
 * Dành cho Free Fire iOS / TrollStore / Sideloadly / Scarlet / Jailbreak
 * - Tác giả: tkietn
 * - Giao thức: HTTP/HTTPS REST API (zkvauth.site)
 * - Tương thích: iOS 14.0 - iOS 18.x (ARM64 / ARM64e)
 * ============================================================================
 */

#import <UIKit/UIKit.h>
#import <Foundation/Foundation.h>
#import <Security/Security.h>
#import <CommonCrypto/CommonCrypto.h>
#import <sys/sysctl.h>
#include <sys/types.h>
#include <unistd.h>

// ==========================================
// CẤU HÌNH SERVER AUTH CỦA ĐẠI CA
// ==========================================
#define TKIETN_SERVER_URL   @"http://zkvauth.site/verify.php"
#define TKIETN_OWNER_NAME   @"tkietn"
#define TKIETN_API_NAME     @"IOS_MOD"
#define TKIETN_TELEGRAM     @"https://t.me/tkietn"

@interface TkietnAuthResult : NSObject
@property (nonatomic, assign) BOOL success;
@property (nonatomic, strong) NSString *message;
@property (nonatomic, strong) NSString *expiryDate;
@property (nonatomic, assign) NSInteger remainingDays;
@end

@implementation TkietnAuthResult
@end

@interface TkietnAuthSessionDelegate : NSObject <NSURLSessionDelegate>
@end

@implementation TkietnAuthSessionDelegate
- (void)URLSession:(NSURLSession *)session 
didReceiveChallenge:(NSURLAuthenticationChallenge *)challenge 
 completionHandler:(void (^)(NSURLSessionAuthChallengeDisposition disposition, NSURLCredential * _Nullable credential))completionHandler {
    // Bỏ qua lỗi SSL nếu server dùng Self-Signed hoặc chưa kích hoạt HTTPS
    if ([challenge.protectionSpace.authenticationMethod isEqualToString:NSURLAuthenticationMethodServerTrust]) {
        completionHandler(NSURLSessionAuthChallengeUseCredential, 
                          [[NSURLCredential alloc] initWithTrust:challenge.protectionSpace.serverTrust]);
    } else {
        completionHandler(NSURLSessionAuthChallengePerformDefaultHandling, nil);
    }
}
@end

@interface TkietnAuthIOS : NSObject

+ (instancetype)sharedInstance;
+ (NSString *)getDeviceHWID;
+ (void)verifyLicense:(NSString *)licenseKey completion:(void(^)(TkietnAuthResult *result))completion;
+ (void)startWatchdog;
+ (void)showLoginPrompt;

@end

@implementation TkietnAuthIOS

+ (instancetype)sharedInstance {
    static TkietnAuthIOS *instance = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        instance = [[TkietnAuthIOS alloc] init];
    });
    return instance;
}

// 1. LẤY MÃ PHẦN CỨNG THIẾT BỊ (HWID)
+ (NSString *)getDeviceHWID {
    NSString *idfv = [[[UIDevice currentDevice] identifierForVendor] UUIDString];
    if (idfv && idfv.length > 5) {
        return idfv;
    }
    
    NSString *keychainKey = @"com.tkietn.auth.hwid";
    NSDictionary *query = @{
        (__bridge id)kSecClass: (__bridge id)kSecClassGenericPassword,
        (__bridge id)kSecAttrAccount: keychainKey,
        (__bridge id)kSecReturnData: @YES,
        (__bridge id)kSecMatchLimit: (__bridge id)kSecMatchLimitOne
    };
    CFTypeRef dataTypeRef = NULL;
    if (SecItemCopyMatching((__bridge CFDictionaryRef)query, &dataTypeRef) == errSecSuccess) {
        NSData *data = (__bridge_transfer NSData *)dataTypeRef;
        NSString *savedUUID = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
        if (savedUUID && savedUUID.length > 5) return savedUUID;
    }
    
    NSString *newUUID = [[NSUUID UUID] UUIDString];
    NSData *uuidData = [newUUID dataUsingEncoding:NSUTF8StringEncoding];
    NSDictionary *addQuery = @{
        (__bridge id)kSecClass: (__bridge id)kSecClassGenericPassword,
        (__bridge id)kSecAttrAccount: keychainKey,
        (__bridge id)kSecValueData: uuidData
    };
    SecItemAdd((__bridge CFDictionaryRef)addQuery, NULL);
    return newUUID;
}

// 2. CHỐNG DEBUGGER (LLDB / FRIDA)
+ (void)startWatchdog {
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_BACKGROUND, 0), ^{
        while (1) {
            int name[4] = {CTL_KERN, KERN_PROC, KERN_PROC_PID, getpid()};
            struct kinfo_proc info;
            size_t info_size = sizeof(info);
            info.kp_proc.p_flag = 0;
            if (sysctl(name, 4, &info, &info_size, NULL, 0) == 0) {
                if ((info.kp_proc.p_flag & P_TRACED) != 0) {
                    NSLog(@"[!] TKIETN-AUTH: Detected Debugger! Terminating...");
                    exit(0);
                }
            }
            [NSThread sleepForTimeInterval:5.0];
        }
    });
}

// 3. XÁC THỰC LICENSE KEY TRỰC TIẾP VỚI SERVER
+ (void)verifyLicense:(NSString *)licenseKey completion:(void(^)(TkietnAuthResult *result))completion {
    NSString *hwid = [self getDeviceHWID];
    NSString *cleanKey = [licenseKey stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    
    NSURLComponents *components = [NSURLComponents componentsWithString:TKIETN_SERVER_URL];
    components.queryItems = @[
        [NSURLQueryItem queryItemWithName:@"owner" value:TKIETN_OWNER_NAME],
        [NSURLQueryItem queryItemWithName:@"api" value:TKIETN_API_NAME],
        [NSURLQueryItem queryItemWithName:@"key" value:cleanKey],
        [NSURLQueryItem queryItemWithName:@"hwid" value:hwid]
    ];
    
    NSURL *url = components.URL;
    NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:url];
    [request setHTTPMethod:@"GET"];
    [request setTimeoutInterval:8.0];
    [request setValue:@"TkietnAuth-iOS/2.0" forHTTPHeaderField:@"User-Agent"];
    
    NSURLSessionConfiguration *config = [NSURLSessionConfiguration defaultSessionConfiguration];
    TkietnAuthSessionDelegate *del = [[TkietnAuthSessionDelegate alloc] init];
    NSURLSession *session = [NSURLSession sessionWithConfiguration:config delegate:del delegateQueue:nil];
    
    [[session dataTaskWithRequest:request completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
        TkietnAuthResult *res = [[TkietnAuthResult alloc] init];
        
        if (error || !data) {
            res.success = NO;
            res.message = [NSString stringWithFormat:@"Không thể kết nối Server (%@)", error.localizedDescription ?: @"Timeout"];
            dispatch_async(dispatch_get_main_queue(), ^{ completion(res); });
            return;
        }
        
        NSError *jsonErr = nil;
        NSDictionary *json = [NSJSONSerialization JSONObjectWithData:data options:0 error:&jsonErr];
        if (jsonErr || !json) {
            res.success = NO;
            res.message = @"Server phản hồi dữ liệu lỗi!";
            dispatch_async(dispatch_get_main_queue(), ^{ completion(res); });
            return;
        }
        
        res.success = [json[@"valid"] boolValue];
        res.message = json[@"message"] ?: (res.success ? @"Kích hoạt thành công!" : @"Key không hợp lệ!");
        res.expiryDate = json[@"expiry"] ?: @"Vĩnh Viễn";
        res.remainingDays = [json[@"days_left"] integerValue];
        
        dispatch_async(dispatch_get_main_queue(), ^{ completion(res); });
    }] resume];
}

// 4. HIỂN THỊ GIAO DIỆN ĐĂNG NHẬP VIP
+ (void)showLoginPrompt {
    dispatch_async(dispatch_get_main_queue(), ^{
        UIWindow *window = nil;
        if (@available(iOS 13.0, *)) {
            for (UIWindowScene *scene in [UIApplication sharedApplication].connectedScenes) {
                if (scene.activationState == UISceneActivationStateForegroundActive) {
                    for (UIWindow *w in scene.windows) {
                        if (w.isKeyWindow) { window = w; break; }
                    }
                }
                if (window) break;
            }
        }
        if (!window) {
            window = [UIApplication sharedApplication].keyWindow ?: [UIApplication sharedApplication].windows.firstObject;
        }
        
        UIViewController *rootVC = window.rootViewController;
        if (!rootVC) {
            // Thử lại sau 1 giây nếu game chưa khởi tạo xong View
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.0 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
                [self showLoginPrompt];
            });
            return;
        }
        while (rootVC.presentedViewController) rootVC = rootVC.presentedViewController;
        
        NSString *hwid = [self getDeviceHWID];
        NSString *savedKey = [[NSUserDefaults standardUserDefaults] objectForKey:@"TKIETN_AUTH_SAVED_KEY"] ?: @"";
        
        UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"🔑 TKIETN-AUTH VIP LOGIN"
                                                                       message:[NSString stringWithFormat:@"Dự án: FreeFire iOS VIP\nHWID: %@", hwid]
                                                                preferredStyle:UIAlertControllerStyleAlert];
        
        [alert addTextFieldWithConfigurationHandler:^(UITextField * _Nonnull textField) {
            textField.placeholder = @"Nhập License Key (TKIETN-VIP-...)";
            textField.text = savedKey;
            textField.autocapitalizationType = UITextAutocapitalizationTypeAllCharacters;
            textField.clearButtonMode = UITextFieldViewModeWhileEditing;
        }];
        
        // Nút Đăng nhập
        UIAlertAction *loginAction = [UIAlertAction actionWithTitle:@"⚡ Đăng Nhập" style:UIAlertActionStyleDefault handler:^(UIAlertAction * _Nonnull action) {
            NSString *inputKey = alert.textFields.firstObject.text;
            if (!inputKey || inputKey.length == 0) {
                [self showLoginPrompt];
                return;
            }
            
            // Hiển thị vòng quay loading
            UIAlertController *loadingAlert = [UIAlertController alertControllerWithTitle:@"Đang xác thực..."
                                                                                  message:@"Đang liên hệ máy chủ zkvauth.site..."
                                                                           preferredStyle:UIAlertControllerStyleAlert];
            [rootVC presentViewController:loadingAlert animated:YES completion:^{
                [self verifyLicense:inputKey completion:^(TkietnAuthResult *result) {
                    [loadingAlert dismissViewControllerAnimated:YES completion:^{
                        if (result.success) {
                            [[NSUserDefaults standardUserDefaults] setObject:inputKey forKey:@"TKIETN_AUTH_SAVED_KEY"];
                            [[NSUserDefaults standardUserDefaults] synchronize];
                            
                            UIAlertController *okAlert = [UIAlertController alertControllerWithTitle:@"🟢 ĐĂNG NHẬP THÀNH CÔNG"
                                                                                             message:[NSString stringWithFormat:@"Chào mừng Đại ca!\nHạn dùng: %@\nChúc Đại ca chơi game vui vẻ!", result.expiryDate]
                                                                                      preferredStyle:UIAlertControllerStyleAlert];
                            [okAlert addAction:[UIAlertAction actionWithTitle:@"Vào Game" style:UIAlertActionStyleDefault handler:nil]];
                            [rootVC presentViewController:okAlert animated:YES completion:nil];
                        } else {
                            UIAlertController *failAlert = [UIAlertController alertControllerWithTitle:@"🔴 XÁC THỰC THẤT BẠI"
                                                                                               message:result.message
                                                                                        preferredStyle:UIAlertControllerStyleAlert];
                            [failAlert addAction:[UIAlertAction actionWithTitle:@"Thử Lại" style:UIAlertActionStyleDefault handler:^(UIAlertAction * _Nonnull a) {
                                [self showLoginPrompt];
                            }]];
                            [rootVC presentViewController:failAlert animated:YES completion:nil];
                        }
                    }];
                }];
            }];
        }];
        
        // Nút Sao chép HWID
        UIAlertAction *copyHwidAction = [UIAlertAction actionWithTitle:@"📋 Copy HWID" style:UIAlertActionStyleDefault handler:^(UIAlertAction * _Nonnull action) {
            [UIPasteboard generalPasteboard].string = hwid;
            [self showLoginPrompt];
        }];
        
        // Nút Lấy Key / Mua Key
        UIAlertAction *buyAction = [UIAlertAction actionWithTitle:@"💬 Lấy Key VIP" style:UIAlertActionStyleDestructive handler:^(UIAlertAction * _Nonnull action) {
            [[UIApplication sharedApplication] openURL:[NSURL URLWithString:TKIETN_TELEGRAM] options:@{} completionHandler:nil];
            [self showLoginPrompt];
        }];
        
        [alert addAction:loginAction];
        [alert addAction:copyHwidAction];
        [alert addAction:buyAction];
        
        [rootVC presentViewController:alert animated:YES completion:nil];
    });
}

@end

// ==========================================
// TỰ ĐỘNG CHẠY KHI DYLIB ĐƯỢC LOAD VÀO GAME
// ==========================================
__attribute__((constructor)) static void TkietnAuthAutoInit() {
    [TkietnAuthIOS startWatchdog];
    
    // Đợi 2.5 giây cho Splash / Engine Unity khởi tạo xong UIWindow
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(2.5 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        [TkietnAuthIOS showLoginPrompt];
    });
}
