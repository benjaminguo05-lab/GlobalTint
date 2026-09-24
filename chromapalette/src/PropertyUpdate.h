#import <Foundation/Foundation.h>

// Foundation-only update engine, also exercised by the macOS regression test.
static inline id CPBoxValue(id value) { return value ?: NSNull.null; }
static inline id CPUnboxValue(id value) { return value == NSNull.null ? nil : value; }
static inline void CPInvalidatePropertyRecords(NSMutableDictionary *records) {
    // Lifecycle reconciliation never clears the conflict breaker or its write budget.
    for (NSMutableDictionary *record in records.allValues) record[@"dirty"]=@YES;
}
static inline BOOL CPSameValue(id a, id b) { return a == b || (a && b && [a isEqual:b]); }
static inline void CPPropertySourceChanged(NSMutableDictionary *record, id value) {
    if (!record || CPSameValue(value, CPUnboxValue(record[@"output"]))) return;
    record[@"source"] = CPBoxValue(value);
    record[@"dirty"] = @YES;
}
// Only call for value-semantic colors or immutable images, never copy-on-get appearances.
static inline void CPPropertyConcreteInput(NSMutableDictionary *record, id current, id context) {
    if (!record) return;
    CPPropertySourceChanged(record, current);
    if (!CPSameValue(record[@"context"], CPBoxValue(context))) {
        record[@"context"] = CPBoxValue(context);
        record[@"dirty"] = @YES;
    }
}

// Returns YES only when a repeated host/plugin conflict trips the circuit breaker.
static inline BOOL CPUpdateProperty(NSMutableDictionary *records, NSString *property,
    BOOL enabled, NSUInteger revision, NSInteger style, double now,
    id (^readValue)(void), void (^writeValue)(id), id (^transform)(id)) {
    NSMutableDictionary *record = records[property];
    if (!enabled) {
        if (!record) return NO;
        id source = CPUnboxValue(record[@"source"]);
        // Remove before restoring, so synchronous nested layout cannot restore twice.
        [records removeObjectForKey:property];
        if (!CPSameValue(readValue(), source)) writeValue(source);
        return NO;
    }
    if (!record) {
        record = [@{@"source":CPBoxValue(readValue()), @"dirty":@YES} mutableCopy];
        records[property] = record;
    }
    BOOL newRevision = !record[@"revision"] || [record[@"revision"] unsignedIntegerValue] != revision;
    if (newRevision) {
        record[@"blocked"] = @NO; record[@"writes"] = @0;
        record[@"window"] = @(now);
    } else {
        if ([record[@"blocked"] boolValue]) return NO;
        // Copy-on-set and copy-on-get properties need not preserve object identity.
        // Only explicit host updates, settings changes, or this view's style invalidate.
        if (![record[@"dirty"] boolValue] && [record[@"style"] integerValue] == style) return NO;
    }
    id current = readValue();
    id desired = transform(CPUnboxValue(record[@"source"]));
    record[@"revision"] = @(revision); record[@"style"] = @(style);
    record[@"dirty"] = @NO;
    if (!CPSameValue(current, desired)) {
        if (now - [record[@"window"] doubleValue] >= 1.0) {
            record[@"window"] = @(now); record[@"writes"] = @0;
        }
        NSUInteger writes = [record[@"writes"] unsignedIntegerValue];
        if (writes >= 8) { record[@"blocked"] = @YES; return YES; }
        record[@"writes"] = @(writes + 1);
        record[@"output"] = CPBoxValue(desired);
        writeValue(desired);
    }
    record[@"output"] = CPBoxValue(readValue());
    return NO;
}
