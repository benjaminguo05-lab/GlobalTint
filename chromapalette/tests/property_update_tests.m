#import "../src/PropertyUpdate.h"
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
        puts("Property update regressions passed: copy identity, host updates, traits, restoration, conflict breaker.");
    }
    return 0;
}
