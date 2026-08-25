#import "GTAppIcon.h"

#import <objc/message.h>
#import <objc/runtime.h>
#import <dlfcn.h>

static UIImage *GTUIKitApplicationIcon(NSString *bundleIdentifier) {
    if (bundleIdentifier.length == 0) {
        return nil;
    }

    SEL selector =
        NSSelectorFromString(
            @"_applicationIconImageForBundleIdentifier:format:scale:"
        );

    Class imageClass = [UIImage class];

    if (![imageClass respondsToSelector:selector]) {
        return nil;
    }

    typedef UIImage *(*GTUIKitIconFunction)(
        id,
        SEL,
        NSString *,
        NSInteger,
        CGFloat
    );

    GTUIKitIconFunction function =
        (GTUIKitIconFunction)objc_msgSend;

    CGFloat scale =
        UIScreen.mainScreen.scale;

    for (NSInteger format = 2;
         format >= 0;
         format--) {

        UIImage *image =
            function(
                imageClass,
                selector,
                bundleIdentifier,
                format,
                scale
            );

        if ([image isKindOfClass:[UIImage class]] &&
            image.size.width > 0.0 &&
            image.size.height > 0.0) {
            return image;
        }
    }

    return nil;
}

static void GTLoadLaunchServicesForIcons(void) {
    static dispatch_once_t onceToken;

    dispatch_once(&onceToken, ^{
        dlopen(
            "/System/Library/Frameworks/CoreServices.framework/CoreServices",
            RTLD_LAZY | RTLD_LOCAL
        );

        dlopen(
            "/System/Library/Frameworks/MobileCoreServices.framework/MobileCoreServices",
            RTLD_LAZY | RTLD_LOCAL
        );
    });
}

static UIImage *GTLaunchServicesApplicationIcon(
    NSString *bundleIdentifier
) {
    GTLoadLaunchServicesForIcons();

    Class proxyClass =
        NSClassFromString(@"LSApplicationProxy");

    SEL proxySelector =
        NSSelectorFromString(
            @"applicationProxyForIdentifier:"
        );

    if (!proxyClass ||
        ![proxyClass respondsToSelector:proxySelector]) {
        return nil;
    }

    typedef id (*GTProxyFunction)(
        id,
        SEL,
        NSString *
    );

    id proxy =
        ((GTProxyFunction)objc_msgSend)(
            proxyClass,
            proxySelector,
            bundleIdentifier
        );

    if (!proxy) {
        return nil;
    }

    SEL iconSelector =
        NSSelectorFromString(@"iconDataForVariant:");

    if (![proxy respondsToSelector:iconSelector]) {
        return nil;
    }

    typedef id (*GTIconDataFunction)(
        id,
        SEL,
        NSUInteger
    );

    GTIconDataFunction function =
        (GTIconDataFunction)objc_msgSend;

    for (NSUInteger variant = 2;
         variant <= 6;
         variant++) {

        id data =
            function(
                proxy,
                iconSelector,
                variant
            );

        if (![data isKindOfClass:[NSData class]] ||
            [(NSData *)data length] == 0) {
            continue;
        }

        UIImage *image =
            [UIImage imageWithData:data];

        if (image) {
            return image;
        }
    }

    return nil;
}

static UIImage *GTGeneratedApplicationIcon(
    NSString *bundleIdentifier
) {
    NSString *source =
        bundleIdentifier.length > 0
        ? bundleIdentifier
        : @"?";

    NSString *letter =
        [[source substringToIndex:1]
         uppercaseString];

    CGSize size =
        CGSizeMake(60.0, 60.0);

    UIGraphicsImageRenderer *renderer =
        [[UIGraphicsImageRenderer alloc]
         initWithSize:size];

    return [renderer imageWithActions:
        ^(UIGraphicsImageRendererContext *context) {

        CGRect bounds =
            CGRectMake(
                0.0,
                0.0,
                size.width,
                size.height
            );

        UIBezierPath *shape =
            [UIBezierPath
             bezierPathWithRoundedRect:bounds
                          cornerRadius:13.0];

        [[UIColor secondarySystemFillColor]
         setFill];

        [shape fill];

        NSDictionary *attributes = @{
            NSFontAttributeName:
                [UIFont
                 systemFontOfSize:25.0
                           weight:UIFontWeightSemibold],

            NSForegroundColorAttributeName:
                UIColor.labelColor
        };

        CGSize textSize =
            [letter sizeWithAttributes:attributes];

        CGRect textRect =
            CGRectMake(
                (size.width - textSize.width) / 2.0,
                (size.height - textSize.height) / 2.0,
                textSize.width,
                textSize.height
            );

        [letter drawInRect:textRect
           withAttributes:attributes];
    }];
}

UIImage *
GTApplicationIconForBundleIdentifier(
    NSString *bundleIdentifier
) {
    static NSCache<NSString *, UIImage *> *cache = nil;
    static dispatch_once_t onceToken;

    dispatch_once(&onceToken, ^{
        cache = [[NSCache alloc] init];
        cache.countLimit = 256;
    });

    NSString *key =
        bundleIdentifier.lowercaseString ?: @"";

    if (key.length == 0) {
        return GTGeneratedApplicationIcon(@"?");
    }

    UIImage *cached =
        [cache objectForKey:key];

    if (cached) {
        return cached;
    }

    UIImage *image =
        GTUIKitApplicationIcon(bundleIdentifier);

    if (!image) {
        image =
            GTLaunchServicesApplicationIcon(
                bundleIdentifier
            );
    }

    if (!image) {
        image =
            GTGeneratedApplicationIcon(
                bundleIdentifier
            );
    }

    [cache setObject:image
              forKey:key];

    return image;
}
