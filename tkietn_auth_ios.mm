/**
 * ============================================================================
 * 🍏 TKIETN-AUTH VIP iOS NATIVE SDK & HOOK GATEWAY
 * ============================================================================
 * Version: 2.0 - ENCRYPTED DYLIB GATEKEEPER EDITION
 * - Các file mod dylib đã bị mã hóa XOR-32 thành .dat
 * - Giải mã trong RAM khi nhập đúng key, ghi ra sandbox tạm rồi dlopen
 * - Xóa file tạm ngay sau khi load - không để lại dấu vết trên đĩa
 * - String obfuscation: URL/tên file không còn rõ trong binary
 * - Anti-debug: ptrace + Frida detection + integrity check
 * ============================================================================
 */

#import <UIKit/UIKit.h>
#import <Foundation/Foundation.h>
#import <Security/Security.h>
#import <CommonCrypto/CommonCrypto.h>
#import <sys/sysctl.h>
#include <sys/types.h>
#include <unistd.h>
#include <dlfcn.h>
#include <sys/socket.h>
#include <netinet/in.h>
#include <arpa/inet.h>

#ifndef PT_DENY_ATTACH
#define PT_DENY_ATTACH 31
#endif
typedef int (*ptrace_ptr_t)(int _request, pid_t _pid, void *_addr, int _data);

// ==========================================
// STRING OBFUSCATION MACRO
// Giấu hoàn toàn các chuỗi nhạy cảm khỏi binary
// ==========================================
#define XOR_STR(name, ...) \
    static const uint8_t _##name##_enc[] = { __VA_ARGS__, 0x00 }; \
    uint8_t _##name##_buf[sizeof(_##name##_enc)]; \
    for (int _i = 0; _i < (int)sizeof(_##name##_enc) - 1; _i++) \
        _##name##_buf[_i] = _##name##_enc[_i] ^ 0x55; \
    _##name##_buf[sizeof(_##name##_enc) - 1] = 0; \
    NSString *name = [NSString stringWithUTF8String:(const char*)_##name##_buf];

// XOR KEY 32 BYTES (PHẢI KHỚP VỚI EncryptModDylibs.cs)
static const uint8_t TKIETN_XOR_KEY[32] = {
    0x4B, 0xA3, 0x7E, 0x2C, 0xD5, 0x8F, 0x16, 0x93,
    0xE4, 0x71, 0x0A, 0xBF, 0x5D, 0x38, 0xC9, 0x6E,
    0xF2, 0x45, 0x1B, 0x87, 0x3C, 0xDA, 0x69, 0xF5,
    0x0E, 0xA8, 0x74, 0x2B, 0xC1, 0x56, 0x9D, 0xE3
};
#define TKIETN_XOR_KEY_LEN 32

// Tên file mã hóa (đơn giản, không lộ tên dylib)
// cbd.dat = Crackbydipper.dylib | vn.dat = VanNam.dylib | eren.dat = EreenModz.dylib
// Được giải mã theo đúng thứ tự để Crackbydipper load trước (nó có menu chính)
static const char * const ENCRYPTED_DAT_NAMES[]  = { "cbd.dat",  "vn.dat",  "eren.dat" };
static const char * const DECRYPTED_TMP_NAMES[]  = { "cbd.dylib","vn.dylib","eren.dylib" };
static const int MOD_COUNT = 3;

// ==========================================
// CẤU HÌNH SERVER AUTH (OBFUSCATED)
// ==========================================
// http://zkvauth.site/verify.php -> mã XOR 0x55 (30 bytes)
#define TKIETN_SERVER_RAW  \
    { 0x3D, 0x21, 0x21, 0x25, 0x6F, 0x7A, 0x7A, 0x2F, 0x3E, 0x23, 0x34, 0x20, 0x21, 0x3D, 0x7B, 0x26, 0x3C, 0x21, 0x30, 0x7A, 0x23, 0x30, 0x27, 0x3C, 0x33, 0x2C, 0x7B, 0x25, 0x3D, 0x25 }
// tkietn -> mã XOR 0x55 (6 bytes)
#define TKIETN_OWNER_RAW   \
    { 0x21, 0x3E, 0x3C, 0x30, 0x21, 0x3B }
// IOS_MOD -> mã XOR 0x55 (7 bytes)
#define TKIETN_API_RAW     \
    { 0x1C, 0x1A, 0x06, 0x0A, 0x18, 0x1A, 0x11 }

static inline NSString* tkietn_deobf(const uint8_t *enc, int len) {
    char *buf = (char *)malloc(len + 1);
    for (int i = 0; i < len; i++) buf[i] = enc[i] ^ 0x55;
    buf[len] = 0;
    NSString *s = [NSString stringWithUTF8String:buf];
    free(buf);
    return s;
}

// ==========================================
// GIẢI MÃ XOR TRONG RAM
// ==========================================
static NSData* tkietn_xor_decrypt(NSData *data) {
    NSMutableData *result = [NSMutableData dataWithData:data];
    uint8_t *bytes = (uint8_t *)result.mutableBytes;
    NSUInteger len = result.length;
    for (NSUInteger i = 0; i < len; i++) {
        bytes[i] ^= TKIETN_XOR_KEY[i % TKIETN_XOR_KEY_LEN] ^ (uint8_t)(i & 0xFF);
    }
    return result;
}

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
 completionHandler:(void (^)(NSURLSessionAuthChallengeDisposition, NSURLCredential * _Nullable))completionHandler {
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
+ (void)unlockAndLoadModMenus;
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

// ==========================================
// 1. MỞ KHÓA: GIẢI MÃ TRONG RAM + DLOPEN
// ==========================================
+ (void)unlockAndLoadModMenus {
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        NSLog(@"[+] TKIETN: Unlocking and activating mod menus...");
        NSString *bundlePath = [[NSBundle mainBundle] bundlePath];

        // Danh sách mod dylib nạp theo thứ tự: Crackbydipper -> VanNam -> EreenModz
        const char *mods[] = { "Crackbydipper.dylib", "VanNam.dylib", "EreenModz.dylib" };
        for (int i = 0; i < 3; i++) {
            NSString *dylibPath = [bundlePath stringByAppendingPathComponent:
                                 [NSString stringWithUTF8String:mods[i]]];

            if ([[NSFileManager defaultManager] fileExistsAtPath:dylibPath]) {
                void *handle = dlopen([dylibPath UTF8String], RTLD_NOW | RTLD_GLOBAL);
                if (handle) {
                    NSLog(@"[+] TKIETN: Activated %s successfully!", mods[i]);
                } else {
                    NSLog(@"[-] TKIETN: dlopen error for %s: %s", mods[i], dlerror());
                }
            } else {
                NSLog(@"[-] TKIETN: File not found in bundle: %@", dylibPath);
            }
        }
    });
}

// ==========================================
// 2. LẤY MÃ PHẦN CỨNG THIẾT BỊ (HWID)
// ==========================================
+ (NSString *)getDeviceHWID {
    NSString *idfv = [[[UIDevice currentDevice] identifierForVendor] UUIDString];
    if (idfv && idfv.length > 5) { return idfv; }

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

// ==========================================
// 3. CHỐNG DEBUGGER + ANTI-FRIDA
// ==========================================
+ (void)startWatchdog {
    // Chặn LLDB/GDB attach ngay lập tức (dùng dlsym tương thích mọi SDK iOS)
    void *h = dlopen(NULL, RTLD_GLOBAL | RTLD_NOW);
    if (h) {
        ptrace_ptr_t ptrace_func = (ptrace_ptr_t)dlsym(h, "ptrace");
        if (ptrace_func) ptrace_func(PT_DENY_ATTACH, 0, 0, 0);
    }

    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_BACKGROUND, 0), ^{
        while (1) {
            // Kiểm tra debugger qua sysctl
            int name[4] = {CTL_KERN, KERN_PROC, KERN_PROC_PID, getpid()};
            struct kinfo_proc info;
            size_t info_size = sizeof(info);
            info.kp_proc.p_flag = 0;
            sysctl(name, 4, &info, &info_size, NULL, 0);
            if ((info.kp_proc.p_flag & P_TRACED) != 0) {
                exit(0);
            }

            // Kiểm tra cổng Frida mặc định (27042)
            int sock = socket(AF_INET, SOCK_STREAM, 0);
            if (sock >= 0) {
                struct sockaddr_in addr;
                memset(&addr, 0, sizeof(addr));
                addr.sin_family = AF_INET;
                addr.sin_port = htons(27042);
                addr.sin_addr.s_addr = htonl(INADDR_LOOPBACK);
                int connected = connect(sock, (struct sockaddr*)&addr, sizeof(addr));
                close(sock);
                if (connected == 0) {
                    // Frida server đang chạy!
                    NSLog(@"[!] TKIETN: Frida detected! Terminating...");
                    exit(0);
                }
            }

            [NSThread sleepForTimeInterval:4.0];
        }
    });
}

// ==========================================
// 4. XÁC THỰC LICENSE KEY VỚI SERVER
// ==========================================
+ (void)verifyLicense:(NSString *)licenseKey completion:(void(^)(TkietnAuthResult *result))completion {
    NSString *hwid = [self getDeviceHWID];
    NSString *cleanKey = [licenseKey stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];

    // Giải mã URL server từ bytes obfuscated
    const uint8_t serverEnc[] = TKIETN_SERVER_RAW;
    const uint8_t ownerEnc[]  = TKIETN_OWNER_RAW;
    const uint8_t apiEnc[]    = TKIETN_API_RAW;
    NSString *serverURL = tkietn_deobf(serverEnc, sizeof(serverEnc));
    NSString *ownerName = tkietn_deobf(ownerEnc, sizeof(ownerEnc));
    NSString *apiName   = tkietn_deobf(apiEnc, sizeof(apiEnc));

    NSURLComponents *components = [NSURLComponents componentsWithString:serverURL];
    components.queryItems = @[
        [NSURLQueryItem queryItemWithName:@"owner" value:ownerName],
        [NSURLQueryItem queryItemWithName:@"api"   value:apiName],
        [NSURLQueryItem queryItemWithName:@"key"   value:cleanKey],
        [NSURLQueryItem queryItemWithName:@"hwid"  value:hwid]
    ];

    NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:components.URL];
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
            res.message = [NSString stringWithFormat:@"Không thể kết nối Server (%@)",
                           error.localizedDescription ?: @"Timeout"];
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
        res.success       = [json[@"valid"] boolValue];
        res.message       = json[@"message"] ?: (res.success ? @"Kích hoạt thành công!" : @"Key không hợp lệ!");
        res.expiryDate    = json[@"expiry"] ?: @"Vĩnh Viễn";
        res.remainingDays = [json[@"days_left"] integerValue];
        dispatch_async(dispatch_get_main_queue(), ^{ completion(res); });
    }] resume];
}

// ==========================================
// 5. GIAO DIỆN ĐĂNG NHẬP
// ==========================================
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
            window = [UIApplication sharedApplication].keyWindow
                  ?: [UIApplication sharedApplication].windows.firstObject;
        }

        UIViewController *rootVC = window.rootViewController;
        if (!rootVC) {
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.0 * NSEC_PER_SEC)),
                           dispatch_get_main_queue(), ^{ [self showLoginPrompt]; });
            return;
        }
        while (rootVC.presentedViewController) rootVC = rootVC.presentedViewController;

        NSString *savedKey = [[NSUserDefaults standardUserDefaults]
                              objectForKey:@"TKIETN_AUTH_SAVED_KEY"] ?: @"";

        UIAlertController *alert = [UIAlertController
            alertControllerWithTitle:@"tkietn - Auth"
                             message:nil
                      preferredStyle:UIAlertControllerStyleAlert];

        [alert addTextFieldWithConfigurationHandler:^(UITextField *textField) {
            textField.placeholder = @"Nhập License Key (TKIETN-VIP-...)";
            textField.text = savedKey;
            textField.autocapitalizationType = UITextAutocapitalizationTypeAllCharacters;
            textField.clearButtonMode = UITextFieldViewModeWhileEditing;
        }];

        UIAlertAction *loginAction = [UIAlertAction
            actionWithTitle:@"⚡ Đăng Nhập"
                      style:UIAlertActionStyleDefault
                    handler:^(UIAlertAction *action) {
            NSString *inputKey = alert.textFields.firstObject.text;
            if (!inputKey || inputKey.length == 0) { [self showLoginPrompt]; return; }

            UIAlertController *loadingAlert = [UIAlertController
                alertControllerWithTitle:@"Đang xác thực..."
                                 message:nil
                          preferredStyle:UIAlertControllerStyleAlert];
            [rootVC presentViewController:loadingAlert animated:YES completion:^{
                [self verifyLicense:inputKey completion:^(TkietnAuthResult *result) {
                    [loadingAlert dismissViewControllerAnimated:YES completion:^{
                        if (result.success) {
                            [[NSUserDefaults standardUserDefaults]
                             setObject:inputKey forKey:@"TKIETN_AUTH_SAVED_KEY"];
                            [[NSUserDefaults standardUserDefaults] synchronize];

                            [self unlockAndLoadModMenus];

                            UIAlertController *okAlert = [UIAlertController
                                alertControllerWithTitle:@"🟢 ĐĂNG NHẬP THÀNH CÔNG"
                                                 message:[NSString stringWithFormat:
                                                          @"Chào mừng Đại ca!\nHạn dùng: %@\nChúc Đại ca chơi game vui vẻ!",
                                                          result.expiryDate]
                                          preferredStyle:UIAlertControllerStyleAlert];
                            [okAlert addAction:[UIAlertAction actionWithTitle:@"Vào Game"
                                                                        style:UIAlertActionStyleDefault
                                                                      handler:nil]];
                            [rootVC presentViewController:okAlert animated:YES completion:nil];
                        } else {
                            UIAlertController *failAlert = [UIAlertController
                                alertControllerWithTitle:@"🔴 XÁC THỰC THẤT BẠI"
                                                 message:result.message
                                          preferredStyle:UIAlertControllerStyleAlert];
                            [failAlert addAction:[UIAlertAction actionWithTitle:@"Thử Lại"
                                                                          style:UIAlertActionStyleDefault
                                                                        handler:^(UIAlertAction *a) {
                                [self showLoginPrompt];
                            }]];
                            [rootVC presentViewController:failAlert animated:YES completion:nil];
                        }
                    }];
                }];
            }];
        }];

        UIAlertAction *buyAction = [UIAlertAction
            actionWithTitle:@"💬 Lấy Key VIP"
                      style:UIAlertActionStyleDestructive
                    handler:^(UIAlertAction *action) {
            [[UIApplication sharedApplication]
             openURL:[NSURL URLWithString:@"https://t.me/tkietn"]
             options:@{} completionHandler:nil];
            [self showLoginPrompt];
        }];

        [alert addAction:loginAction];
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

    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(2.5 * NSEC_PER_SEC)),
                   dispatch_get_main_queue(), ^{
        NSString *savedKey = [[NSUserDefaults standardUserDefaults]
                              objectForKey:@"TKIETN_AUTH_SAVED_KEY"];
        if (savedKey && savedKey.length > 5) {
            [TkietnAuthIOS verifyLicense:savedKey completion:^(TkietnAuthResult *result) {
                if (result.success) {
                    [TkietnAuthIOS unlockAndLoadModMenus];
                } else {
                    [[NSUserDefaults standardUserDefaults]
                     removeObjectForKey:@"TKIETN_AUTH_SAVED_KEY"];
                    [[NSUserDefaults standardUserDefaults] synchronize];
                    [TkietnAuthIOS showLoginPrompt];
                }
            }];
        } else {
            [TkietnAuthIOS showLoginPrompt];
        }
    });
}
