#import "Config.h"
#import <QuartzCore/QuartzCore.h>
#import <objc/runtime.h>
#import <objc/message.h>
#import <substrate.h>

typedef void (^CPViewAction)(UIView *view);
FOUNDATION_EXPORT void CPStart(BOOL systemProcess, dispatch_block_t install);
FOUNDATION_EXPORT UIColor *CPColor(NSString *group, NSString *role, UIView *view);
FOUNDATION_EXPORT BOOL CPGroupEnabled(NSString *group, UIView *view);
FOUNDATION_EXPORT BOOL CPIsSettingsView(UIView *view);
FOUNDATION_EXPORT void CPApplyColor(id object, NSString *property, UIColor *color);
FOUNDATION_EXPORT void CPTransform(id object, NSString *property, BOOL enabled, id (^transform)(id source));
FOUNDATION_EXPORT id CPGetObject(id object, NSString *property);
FOUNDATION_EXPORT id CPGetIvar(id object, const char *name);
FOUNDATION_EXPORT BOOL CPObjectMethod(Class cls, SEL selector, unsigned int arguments);
FOUNDATION_EXPORT BOOL CPVoidObjectMethod(Class cls, SEL selector);
FOUNDATION_EXPORT void CPRegisterView(NSString *className, NSArray<NSString *> *properties, CPViewAction action);
FOUNDATION_EXPORT void CPRecordCapability(NSString *name, BOOL supported);
FOUNDATION_EXPORT void CPInstallComponents(void);
FOUNDATION_EXPORT void CPInstallPrivate(BOOL systemProcess);
