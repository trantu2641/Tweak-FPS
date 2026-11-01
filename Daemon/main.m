
#import <Foundation/Foundation.h>

int main(int argc, char *argv[]) {
    @autoreleasepool {
        NSLog(
            @"[SystemFPSDaemon] Started. "
            @"Filter is managed by the packaged SystemFPS.plist. "
            @"No overwrite performed."
        );
    }

    return 0;
}
