//
//  MMDisplayActions.m
//  Terminal
//
//  Created by Mehdi Mulani on 6/1/13.
//  Copyright (c) 2013 Mehdi Mulani. All rights reserved.
//

#import "MMDisplayActions.h"

@implementation MMDecAlignmentTest

- (void)do;
{
    // This is the DEC Screen Alignment Test and is activated by \033#8.
    // It fills the screen with the letter "E".

    NSInteger numberOfRowsToCreate = self.delegate.termHeight - self.delegate.numberOfRowsOnScreen;
    for (NSInteger i = 0; i < numberOfRowsToCreate; i++) {
        [self.delegate insertBlankLineAtScrollRow:(self.delegate.termHeight - numberOfRowsToCreate + i + 1) withNewline:NO];
    }

    NSString *alignmentText = [@"" stringByPaddingToLength:self.delegate.termWidth withString:@"E" startingAtIndex:0];
    for (NSInteger i = 1; i <= self.delegate.termHeight; i++) {
        [self.delegate replaceCharactersAtScrollRow:i scrollColumn:1 withString:alignmentText];
        [self.delegate setScrollRow:i hasNewline:(i != self.delegate.termHeight)];
    }
}

@end