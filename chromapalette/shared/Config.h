#import "Schema.h"

FOUNDATION_EXPORT NSDictionary *CPReadConfiguration(void);
FOUNDATION_EXPORT BOOL CPWriteConfiguration(NSDictionary *configuration);
FOUNDATION_EXPORT NSDictionary *CPNormalizeConfiguration(id configuration);
FOUNDATION_EXPORT int CPPreparePreferences(void);
