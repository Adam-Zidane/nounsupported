// NoUnsupported v0.2 - SpringBoard only.
// 1) Same idea as "SupportTheUnsupported": make SBUIController never report an unsupported /
//    charge-incapable charging accessory.
// 2) Also closes the "This accessory may not be supported" alert if it still shows up.
#import <UIKit/UIKit.h>
#import <objc/runtime.h>
#include <stdlib.h>

static BOOL gPatched = NO;

static void patchSBUIController(void) {
    if (gPatched) return;
    Class c = objc_getClass("SBUIController");
    if (!c) { NSLog(@"[NoUnsupported] SBUIController not found"); return; }
    unsigned int n = 0;
    Method *list = class_copyMethodList(c, &n);
    int hooked = 0;
    for (unsigned int i = 0; i < n; i++) {
        Method m = list[i];
        SEL sel = method_getName(m);
        NSString *name = NSStringFromSelector(sel);
        if ([name rangeOfString:@"UnsupportedChargingAccessory"].location == NSNotFound &&
            [name rangeOfString:@"ChargeIncapable"].location == NSNotFound) continue;
        IMP orig = method_getImplementation(m);
        if ([name hasPrefix:@"set"]) {
            method_setImplementation(m, imp_implementationWithBlock(^(id s, BOOL v) {
                ((void (*)(id, SEL, BOOL))orig)(s, sel, NO);
            }));
        } else {
            char *rt = method_copyReturnType(m);
            BOOL isBool = (rt && (rt[0] == 'B' || rt[0] == 'c'));
            free(rt);
            if (!isBool) continue;
            method_setImplementation(m, imp_implementationWithBlock(^BOOL(id s) { return NO; }));
        }
        hooked++;
        NSLog(@"[NoUnsupported] patched -[SBUIController %@]", name);
    }
    free(list);
    gPatched = YES;
    if (!hooked) NSLog(@"[NoUnsupported] no matching SBUIController selectors on this iOS");
}

static BOOL looksLikeAccessoryAlert(UIAlertController *a) {
    NSString *t = [NSString stringWithFormat:@"%@ %@", a.title ?: @"", a.message ?: @""].lowercaseString;
    if ([t containsString:@"accessory"] && ([t containsString:@"support"] || [t containsString:@"certif"])) return YES;
    if ([t containsString:@"cable"] && [t containsString:@"certif"]) return YES;
    return NO;
}

static void hookAlerts(void) {
    Method m = class_getInstanceMethod([UIAlertController class], @selector(viewWillAppear:));
    if (!m) return;
    IMP orig = method_getImplementation(m);
    method_setImplementation(m, imp_implementationWithBlock(^(UIAlertController *s, BOOL animated) {
        ((void (*)(id, SEL, BOOL))orig)(s, @selector(viewWillAppear:), animated);
        if (!looksLikeAccessoryAlert(s)) return;
        NSLog(@"[NoUnsupported] closing alert: %@ / %@", s.title, s.message);
        dispatch_async(dispatch_get_main_queue(), ^{
            @try {
                UIAlertAction *act = s.actions.firstObject;
                void (^handler)(UIAlertAction *) = [act valueForKey:@"handler"];
                if (handler) handler(act);
            } @catch (__unused NSException *e) {}
            [s dismissViewControllerAnimated:NO completion:nil];
        });
    }));
}

__attribute__((constructor)) static void nounsupported_init(void) {
    patchSBUIController();
    hookAlerts();
    if (!gPatched) {
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 5 * NSEC_PER_SEC), dispatch_get_main_queue(), ^{
            patchSBUIController();
        });
    }
}
