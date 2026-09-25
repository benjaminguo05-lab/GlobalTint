#import "../src/PropertyUpdate.h"
#import "../src/AttributedColors.h"
#import "../shared/ConfigurationMigration.h"
#import "../src/BluePolicy.h"
#import "../src/FilzaArrowPolicy.h"
#include <assert.h>
#include <stdio.h>

// Deliberately uses NSObject identity equality and returns fresh copies.
@interface CopyValue : NSObject <NSCopying>
@property(nonatomic) NSInteger number;
@end
@implementation CopyValue
- (id)copyWithZone:(NSZone *)zone {
    CopyValue *copy=[CopyValue new]; copy.number=self.number; return copy;
}
@end
static CopyValue *Value(NSInteger number) {
    CopyValue *v=[CopyValue new]; v.number=number; return v;
}
int main(void) {
    @autoreleasepool {
        for (NSString *name in @[@"arrow_up",@"arrow_down",@"e_return",@"e_expand"]) assert(CPFilzaLiveArrowAsset(name));
        for (id other in @[@"no_sort",@"folder",@"arrow_other",@42,NSNull.null]) assert(!CPFilzaLiveArrowAsset(other));
        assert(!CPFilzaLiveArrowAsset(nil));
        // Arrow image was generated and cached before hooks became active.
        // A live-view pass must color it without re-entering the image factory.
        NSMutableDictionary *arrowRecords=[NSMutableDictionary dictionary];
        id blueArrow=[NSObject new], grayArrow=[NSObject new], greenArrow=[NSObject new], redArrow=[NSObject new];
        __block id arrow=blueArrow; __block NSUInteger arrowWrites=0;
        id (^readArrow)(void)=^id { return arrow; };
        void (^writeArrow)(id)=^(id value) { arrow=value; ++arrowWrites; };
        for (NSUInteger pass=0;pass<10000;++pass) {
            CPPropertyConcreteInput(arrowRecords[@"image"],arrow,@"green");
            CPUpdateProperty(arrowRecords,@"image",YES,1,1,0.1,readArrow,writeArrow,^id(id source) { assert(source==blueArrow); return greenArrow; });
        }
        assert(arrow==greenArrow && arrowWrites==1);
        CPPropertyConcreteInput(arrowRecords[@"image"],arrow,@"red");
        CPUpdateProperty(arrowRecords,@"image",YES,2,1,2,readArrow,writeArrow,^id(id source) { assert(source==blueArrow); return redArrow; });
        assert(arrow==redArrow);
        CPUpdateProperty(arrowRecords,@"image",NO,3,1,3,readArrow,writeArrow,^id(id source) { return source; });
        assert(arrow==blueArrow);
        // Changing the sort column replaces the old arrow with a gray idle glyph.
        CPUpdateProperty(arrowRecords,@"image",YES,4,1,4,readArrow,writeArrow,^id(id source) { return greenArrow; });
        arrow=grayArrow; CPPropertyConcreteInput(arrowRecords[@"image"],arrow,nil);
        CPUpdateProperty(arrowRecords,@"image",NO,4,1,4.1,readArrow,writeArrow,^id(id source) { return source; });
        assert(arrow==grayArrow && arrowRecords.count==0);
        NSDictionary *oldRole=@{@"enabled":@YES,@"light":@"#168A60",@"dark":@"#5CDBAA"};
        NSDictionary *old=@{@"enabled":@YES,@"schema":@2,@"groups":@{@"accent":@YES},@"roles":@{@"accent.foreground":oldRole}};
        NSDictionary *wrapper=@{@"configuration":old};
        assert(CPConfigurationPayload(wrapper)==old);
        assert(CPConfigurationPayload(old)==old);
        assert(CPConfigurationPayload(@"invalid")==nil);
        assert(CPConfigurationPayload(@{@"configuration":@"invalid"})==nil);
        NSDictionary *merged=CPMigrateAccent(old);
        assert([merged[@"roles"][@"accent.color"] isEqual:oldRole]);
        assert([merged[@"groups"][@"accent"] boolValue]);
        assert([CPMigrateAccent(merged) isEqual:merged]);
        NSMutableDictionary *off=[old mutableCopy]; off[@"groups"]=@{@"accent":@NO};
        assert(![CPMigrateAccent(off)[@"groups"][@"accent"] boolValue]);
        off[@"roles"]=@{@"accent.color":@"invalid"};
        assert([CPMigrateAccent(off) isKindOfClass:NSDictionary.class]);
        NSDictionary *disabledRole=@{@"enabled":@NO,@"light":@"#123456",@"dark":@"#654321"};
        off[@"roles"]=@{@"filza.accent":disabledRole}; off[@"groups"]=@{@"filza":@YES};
        NSDictionary *fallback=CPMigrateAccent(off);
        assert(![fallback[@"groups"][@"accent"] boolValue]);
        assert([fallback[@"roles"][@"accent.color"][@"light"] isEqual:@"#123456"]);
        assert([fallback[@"roles"][@"accent.color"][@"enabled"] boolValue]);
        assert(CPCanonicalBlue(0,122.0/255,1));
        assert(CPCanonicalBlue(10.0/255,132.0/255,1));
        assert(!CPCanonicalBlue(0,1,1));
        assert(!CPCanonicalBlue(1,0,0));
        assert(!CPCanonicalBlue(1,1,1));
        assert(!CPCanonicalBlue(0.5,0.5,0.5));
        assert(!CPCanonicalBlue(0.1,0.4,0.9));

        NSMutableAttributedString *rich=[[NSMutableAttributedString alloc] initWithString:@"action danger white"];
        [rich addAttributes:@{@"foreground":@"blue",@"underline":@"blue",@"link":@"test://original",@"font":@"unchanged"} range:NSMakeRange(0,6)];
        [rich addAttribute:@"foreground" value:@"red" range:NSMakeRange(7,6)];
        [rich addAttribute:@"foreground" value:@"white" range:NSMakeRange(14,5)];
        NSAttributedString *mapped=CPMapAttributedColors(rich,@[@"foreground",@"underline"],^id(id value) { return [value isEqual:@"blue"] ? @"green" : value; });
        assert([mapped.string isEqual:rich.string]);
        assert([[mapped attribute:@"foreground" atIndex:0 effectiveRange:NULL] isEqual:@"green"]);
        assert([[mapped attribute:@"underline" atIndex:0 effectiveRange:NULL] isEqual:@"green"]);
        assert([[mapped attribute:@"link" atIndex:0 effectiveRange:NULL] isEqual:@"test://original"]);
        assert([[mapped attribute:@"font" atIndex:0 effectiveRange:NULL] isEqual:@"unchanged"]);
        assert([[mapped attribute:@"foreground" atIndex:7 effectiveRange:NULL] isEqual:@"red"]);
        assert([[mapped attribute:@"foreground" atIndex:14 effectiveRange:NULL] isEqual:@"white"]);
        assert([[rich attribute:@"foreground" atIndex:0 effectiveRange:NULL] isEqual:@"blue"]);
        assert(CPMapAttributedColors(mapped,@[@"foreground"],^id(id value) { return value; })==mapped);
        assert(CPMapAttributedColors(nil,@[@"foreground"],^id(id value) { return value; })==nil);
        NSMutableDictionary *records=[NSMutableDictionary dictionary];
        __block CopyValue *stored=Value(10);
        __block NSUInteger writes=0, transforms=0;
        id (^read)(void)=^id { return [stored copy]; };
        void (^write)(id)=^(id value) { stored=[value copy]; ++writes; };
        id (^paint)(id)=^id(id source) { ++transforms; return Value(((CopyValue *)source).number+100); };
        for (NSUInteger i=0;i<10000;i++)
            assert(!CPUpdateProperty(records,@"appearance",YES,1,1,0.1,read,write,paint));
        assert(writes==1 && transforms==1 && stored.number==110);
        // A real host setter changes the baseline; layout then applies once.
        stored=Value(20); CPPropertySourceChanged(records[@"appearance"],stored);
        CPUpdateProperty(records,@"appearance",YES,1,1,0.2,read,write,paint);
        assert(writes==2 && stored.number==120);
        // Trait switch and settings reload invalidate only once each.
        CPUpdateProperty(records,@"appearance",YES,1,2,0.3,read,write,paint);
        CPUpdateProperty(records,@"appearance",YES,2,2,0.4,read,write,paint);
        assert(writes==4 && stored.number==120);
        CPUpdateProperty(records,@"appearance",NO,2,2,0.5,read,write,paint);
        assert(stored.number==20 && writes==5 && records.count==0);
        // Nil baselines restore correctly and restoration is idempotent.
        stored=nil;
        CPUpdateProperty(records,@"appearance",YES,3,1,1,read,write,paint);
        CPUpdateProperty(records,@"appearance",NO,3,1,1,read,write,paint);
        NSUInteger restoredWrites=writes;
        CPUpdateProperty(records,@"appearance",NO,3,1,1,read,write,paint);
        assert(stored==nil && writes==restoredWrites);
        // Simulate a UIKit state update fighting the tweak on every layout.
        writes=0; NSUInteger trips=0;
        for (NSUInteger i=0;i<10000;i++) {
            stored=Value(30);
            CPPropertySourceChanged(records[@"appearance"],stored);
            trips+=CPUpdateProperty(records,@"appearance",YES,4,1,2.0+i*0.00001,read,write,paint);
        }
        assert(writes==8 && trips==1);
        // Waiting does not restart a blocked property; explicit config change does.
        CPUpdateProperty(records,@"appearance",YES,4,1,100,read,write,paint);
        assert(writes==8);
        CPUpdateProperty(records,@"appearance",YES,5,1,101,read,write,paint);
        assert(writes==9);
        // Concrete inputs: host writes made inside layout must be noticed, but stay bounded.
        records=[NSMutableDictionary dictionary];
        __block NSString *actual=@"blue";
        __block NSString *chosen=@"green";
        __block NSUInteger colorWrites=0;
        id (^readColor)(void)=^id { return actual; };
        void (^writeColor)(id)=^(id value) { actual=value; ++colorWrites; };
        id (^paintColor)(id)=^id(id source) { return chosen; };
        for (NSUInteger i=0;i<10000;i++) {
            CPPropertyConcreteInput(records[@"color"],actual,chosen);
            CPUpdateProperty(records,@"color",YES,1,1,0.1,readColor,writeColor,paintColor);
        }
        assert(colorWrites==1 && [actual isEqual:@"green"]);
        chosen=@"gray"; // tab selection changes without a config revision
        CPPropertyConcreteInput(records[@"color"],actual,chosen);
        CPUpdateProperty(records,@"color",YES,1,1,0.2,readColor,writeColor,paintColor);
        assert(colorWrites==2 && [actual isEqual:@"gray"]);
        trips=0;
        for (NSUInteger i=0;i<10000;i++) {
            actual=@"blue";
            CPPropertyConcreteInput(records[@"color"],actual,chosen);
            trips+=CPUpdateProperty(records,@"color",YES,1,1,0.3,readColor,writeColor,paintColor);
        }
        assert(colorWrites==8 && trips==1);
        CPPropertyConcreteInput(records[@"color"],actual,nil);
        CPUpdateProperty(records,@"color",NO,1,1,0.4,readColor,writeColor,paintColor);
        assert([actual isEqual:@"blue"] && records.count==0);
        // Launch/window/trait reconciliation dirties copy properties, but never resets
        // their conflict budget. Even repeated lifecycle events remain bounded.
        records=[NSMutableDictionary dictionary]; stored=Value(10); writes=0; trips=0;
        for (NSUInteger i=0;i<10000;i++) {
            CPInvalidatePropertyRecords(records);
            trips+=CPUpdateProperty(records,@"appearance",YES,6,1,0.1,read,write,paint);
        }
        assert(writes==8 && trips==1);
        CPInvalidatePropertyRecords(records);
        CPUpdateProperty(records,@"appearance",YES,6,2,10.0,read,write,paint);
        assert(writes==8); // a later lifecycle/trait callback does not restart it
        CPUpdateProperty(records,@"appearance",NO,6,2,10.1,read,write,paint);
        assert(stored.number==10);
        // Link display attributes preserve all unrelated metadata and restore exactly.
        records=[NSMutableDictionary dictionary];
        __block NSDictionary *links=@{@"foreground":@"yellow",@"underline":@1,@"custom":@"preserved"};
        NSDictionary *baseline=links;
        __block NSUInteger linkWrites=0;
        id (^readLinks)(void)=^id { return [links copy]; };
        void (^writeLinks)(id)=^(id value) { links=[value copy]; ++linkWrites; };
        id (^paintLinks)(id)=^id(id source) { NSMutableDictionary *a=[source mutableCopy]; a[@"foreground"]=@"green"; return a; };
        for (NSUInteger i=0;i<10000;i++) {
            CPPropertyConcreteInput(records[@"links"],links,@"green");
            CPUpdateProperty(records,@"links",YES,1,1,0.1,readLinks,writeLinks,paintLinks);
        }
        assert(linkWrites==1 && [links[@"custom"] isEqual:@"preserved"] && [links[@"underline"] isEqual:@1]);
        CPUpdateProperty(records,@"links",NO,1,1,0.2,readLinks,writeLinks,paintLinks);
        assert([links isEqual:baseline]);
        puts("Migration, canonical-blue and property update regressions passed: copy identity, host updates, traits, restoration, concrete colors/state, lifecycle budgets, link attributes, conflict breaker.");
    }
    return 0;
}
