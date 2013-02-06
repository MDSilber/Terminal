//
//  MMAppDelegate.h
//  Terminal
//
//  Created by Mehdi Mulani on 1/29/13.
//  Copyright (c) 2013 Mehdi Mulani. All rights reserved.
//

#import <Cocoa/Cocoa.h>

@interface MMAppDelegate : NSObject <NSApplicationDelegate, NSTextFieldDelegate>

@property (retain) IBOutlet NSWindow *window;
@property (retain) IBOutlet NSTextField *commandText;
@property (retain) IBOutlet NSTextView *consoleText;
@property int fd;
@property BOOL running;

@end
