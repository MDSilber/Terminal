//
//  MMTask.m
//  Terminal
//
//  Created by Mehdi Mulani on 2/19/13.
//  Copyright (c) 2013 Mehdi Mulani. All rights reserved.
//

#import "MMTask.h"
#import "MMShared.h"
#import "MMTerminalConnection.h"
#import "MMMoveCursor.h"
#import "MMErasingActions.h"
#import "MMLineManipulationActions.h"
#import "MMIndexActions.h"
#import "MMDisplayActions.h"

@interface MMTask ()

@property NSInteger currentRowOffset;
@property NSString *unreadOutput;
@property BOOL cursorKeyMode;
@property NSInteger scrollMarginTop;
@property NSInteger scrollMarginBottom;
@property NSInteger characterOffsetToScreen;
@property NSMutableArray *characterCountsOnVisibleRows;
@property NSMutableArray *scrollRowHasNewline;
@property NSMutableDictionary *characterAttributes;
@property NSInteger removedTrailingNewlineInScrollLine;
@property BOOL autowrapMode;

@end

@implementation MMTask

- (id)init;
{
    self = [super init];
    if (!self) {
        return nil;
    }

    self.output = [NSMutableString string];

    self.characterCountsOnVisibleRows = [NSMutableArray arrayWithCapacity:TERM_HEIGHT];
    self.scrollRowHasNewline = [NSMutableArray arrayWithCapacity:TERM_HEIGHT];
    for (NSInteger i = 0; i < TERM_HEIGHT; i++) {
        [self.characterCountsOnVisibleRows addObject:@0];
        [self.scrollRowHasNewline addObject:@NO];
    }
    self.removedTrailingNewlineInScrollLine = 0;
    self.currentRowOffset = 0;
    self.cursorPosition = MMPositionMake(1, 1);
    self.scrollMarginTop = 1;
    self.scrollMarginBottom = 24;
    self.characterAttributes = [NSMutableDictionary dictionary];
    self.characterAttributes[NSFontAttributeName] = [NSFont userFixedPitchFontOfSize:[NSFont systemFontSize]];
    self.autowrapMode = YES;

    return self;
}

- (void)handleUserInput:(NSString *)input;
{
    [self.terminalConnection handleTerminalInput:input];
}

- (void)handleCursorKeyInput:(MMArrowKey)arrowKey;
{
    NSString *arrowKeyString = @[@"A", @"B", @"C", @"D"][arrowKey];
    NSString *inputToSend = nil;
    if (self.cursorKeyMode) {
        inputToSend = [@"\033O" stringByAppendingString:arrowKeyString];
    } else {
        inputToSend = [@"\033[" stringByAppendingString:arrowKeyString];
    }
    [self handleUserInput:inputToSend];
}

- (void)handleCommandOutput:(NSString *)output withVerbosity:(BOOL)verbosity;
{
    [self readdTrailingNewlineIfNecessary];

    [self.output appendString:output];

    NSString *outputToHandle = self.unreadOutput ? [self.unreadOutput stringByAppendingString:output] : output;
    NSCharacterSet *nonPrintableCharacters = [NSCharacterSet characterSetWithCharactersInString:@"\n\r\b\a\033"];
    self.unreadOutput = nil;
    for (NSUInteger i = 0; i < [outputToHandle length]; i++) {
        if (self.cursorPosition.y > TERM_HEIGHT) {
            MMLog(@"Cursor position too low");
            break;
        }
        unichar currentChar = [outputToHandle characterAtIndex:i];

        if (![nonPrintableCharacters characterIsMember:currentChar]) {
            NSInteger end = i + 1;
            for (end = i + 1; end < outputToHandle.length && ![nonPrintableCharacters characterIsMember:[outputToHandle characterAtIndex:end]]; end++);

            [self ansiPrint:[outputToHandle substringWithRange:NSMakeRange(i, end - i)]];

            i = end - 1;
            continue;
        }

        if (currentChar == '\n') {
            if (verbosity) {
                MMLog(@"Handling newline.");
            }
            [self addNewline];
        } else if (currentChar == '\r') {
            if (verbosity) {
                MMLog(@"Handling carriage return.");
            }
            MMANSIAction *action = [[MMMoveCursorBackward alloc] initWithArguments:@[@(self.cursorPosition.x - 1)]];
            action.delegate = self;
            [action do];
        } else if (currentChar == '\b') {
            if (verbosity) {
                MMLog(@"Handling backspace.");
            }

            MMANSIAction *action = [[MMMoveCursorBackward alloc] initWithArguments:@[@1]];
            action.delegate = self;
            [action do];
        } else if (currentChar == '\a') { // Bell (beep).
            NSBeep();
            MMLog(@"Beeping.");
        } else if (currentChar == '\033') { // Escape character.
            NSUInteger firstAlphabeticIndex = i;
            if ([outputToHandle length] == (firstAlphabeticIndex + 1)) {
                self.unreadOutput = [outputToHandle substringFromIndex:i];
                break;
            }

            if ([outputToHandle characterAtIndex:(firstAlphabeticIndex + 1)] != '[') {
                // This is where we gather the required characters for escape sequence which does not start with "\033[".
                // The length of these escape sequences vary, so we have to determine whether we have enough output first.
                // TODO: Handle Operating System Controls (i.e. the sequences that start with "\033]").
                NSCharacterSet *prefixesThatRequireAnExtraCharacter = [NSCharacterSet characterSetWithCharactersInString:@" #%()*+"];
                if ([prefixesThatRequireAnExtraCharacter characterIsMember:[outputToHandle characterAtIndex:(firstAlphabeticIndex + 1)]]) {
                    if ([outputToHandle length] == (firstAlphabeticIndex + 2)) {
                        self.unreadOutput = [outputToHandle substringFromIndex:i];
                        break;
                    }

                    [self handleEscapeSequence:[outputToHandle substringWithRange:NSMakeRange(firstAlphabeticIndex, 3)]];
                    i = i + 2;
                    continue;
                } else {
                    [self handleEscapeSequence:[outputToHandle substringWithRange:NSMakeRange(firstAlphabeticIndex, 2)]];
                    i = i + 1;
                    continue;
                }
            }

            NSCharacterSet *lowercaseChars = [NSCharacterSet lowercaseLetterCharacterSet];
            NSCharacterSet *uppercaseChars = [NSCharacterSet uppercaseLetterCharacterSet];
            while (firstAlphabeticIndex < [outputToHandle length] &&
                   ![lowercaseChars characterIsMember:[outputToHandle characterAtIndex:firstAlphabeticIndex]] &&
                   ![uppercaseChars characterIsMember:[outputToHandle characterAtIndex:firstAlphabeticIndex]]) {
                firstAlphabeticIndex++;
            }

            // The escape sequence could be split over multiple reads.
            if (firstAlphabeticIndex == [outputToHandle length]) {
                self.unreadOutput = [outputToHandle substringFromIndex:i];
                break;
            }

            NSString *escapeSequence = [outputToHandle substringWithRange:NSMakeRange(i, firstAlphabeticIndex - i + 1)];
            if (verbosity) {
                MMLog(@"Parsed escape sequence: %@", escapeSequence);
            }
            [self handleEscapeSequence:escapeSequence];
            i = firstAlphabeticIndex;
        }
    }

    [self removeTrailingNewlineIfNecessary];
}

- (BOOL)shouldDrawFullTerminalScreen;
{
    return self.hasUsedWholeScreen || self.numberOfRowsOnScreen > TERM_HEIGHT ||
        (self.numberOfRowsOnScreen == TERM_HEIGHT &&
         ([self numberOfCharactersInScrollRow:TERM_HEIGHT] > 0 ||
          [self isScrollRowTerminatedInNewline:TERM_HEIGHT]));
}

- (void)readdTrailingNewlineIfNecessary;
{
    if (self.removedTrailingNewlineInScrollLine == 0) {
        return;
    }

    [self setScrollRow:self.removedTrailingNewlineInScrollLine hasNewline:YES];
    self.removedTrailingNewlineInScrollLine = 0;
}

- (void)removeTrailingNewlineIfNecessary;
{
    if (!self.finishedAt || self.removedTrailingNewlineInScrollLine != 0) {
        return;
    }

    if (self.displayTextStorage.length > 0 && [[self.displayTextStorage attributedSubstringFromRange:NSMakeRange(self.displayTextStorage.length - 1, 1)].string isEqualToString:@"\n"]) {
        for (NSInteger i = self.numberOfRowsOnScreen; i >= 1; i--) {
            if ([self isScrollRowTerminatedInNewline:i]) {
                self.removedTrailingNewlineInScrollLine = i;
                [self setScrollRow:i hasNewline:NO];
                break;
            }
        }
    }
}

- (void)processFinished;
{
    self.finishedAt = [NSDate date];

    [self removeTrailingNewlineIfNecessary];
}

# pragma mark - ANSI display methods

- (void)adjustNumberOfCharactersOnScrollRow:(NSInteger)row byAmount:(NSInteger)change;
{
    self.characterCountsOnVisibleRows[row - 1] = @([self.characterCountsOnVisibleRows[row - 1] integerValue] + change);
}


- (void)ansiPrint:(NSString *)string;
{
    [self fillCurrentScreenWithSpacesUpToCursor];

    // If we are not in autowrap mode, we only print the characters that will fit on the current line.
    // Furthermore, as per the vt100 wrapping glitch (at http://invisible-island.net/xterm/xterm.faq.html#vt100_wrapping), we only print the "head" of the content to be outputted.
    if (!self.autowrapMode && string.length > (TERM_WIDTH - [self numberOfCharactersInScrollRow:self.cursorPosition.y])) {
        self.cursorPosition = MMPositionMake(MIN(TERM_WIDTH, self.cursorPosition.x), self.cursorPosition.y);
        NSString *charactersToInsertFromHead = [string substringWithRange:NSMakeRange(0, TERM_WIDTH - self.cursorPositionX + 1)];
        string = charactersToInsertFromHead;
    }

    NSInteger i = 0;
    while (i < string.length) {
        if (self.cursorPosition.x == TERM_WIDTH + 1) {
            // If there is a newline present at the end of this line, we clear it as the text will now flow to the next line.
            [self setScrollRow:self.cursorPosition.y hasNewline:NO];
            self.cursorPosition = MMPositionMake(1, self.cursorPosition.y + 1);
            [self checkIfExceededLastLineAndObeyScrollMargin:YES];
        }

        NSInteger lengthToPrintOnLine = MIN(string.length - i, TERM_WIDTH - self.cursorPosition.x + 1);
        NSAttributedString *attributedString = [[NSAttributedString alloc] initWithString:[string substringWithRange:NSMakeRange(i, lengthToPrintOnLine)] attributes:self.characterAttributes];
        NSInteger numberOfCharactersToDelete = MIN(lengthToPrintOnLine, [self numberOfCharactersInScrollRow:self.cursorPosition.y] - self.cursorPosition.x + 1);
        if (numberOfCharactersToDelete > 0) {
            [self.displayTextStorage deleteCharactersInRange:NSMakeRange(self.cursorPositionByCharacters, numberOfCharactersToDelete)];
        }
        [self.displayTextStorage insertAttributedString:attributedString atIndex:self.cursorPositionByCharacters];
        [self adjustNumberOfCharactersOnScrollRow:self.cursorPosition.y byAmount:(lengthToPrintOnLine - numberOfCharactersToDelete)];
        self.cursorPosition = MMPositionMake(self.cursorPosition.x + lengthToPrintOnLine, self.cursorPosition.y);

        i += lengthToPrintOnLine;
    }
}

- (void)addNewline;
{
    [self createBlankLinesUpToCursor];

    [self setScrollRow:self.cursorPosition.y hasNewline:YES];
    self.cursorPosition = MMPositionMake(1, self.cursorPosition.y + 1);

    [self checkIfExceededLastLineAndObeyScrollMargin:YES];
}

- (void)createBlankLinesUpToCursor;
{
    for (NSInteger i = self.numberOfRowsOnScreen; i < self.cursorPosition.y; i++) {
        [self insertBlankLineAtScrollRow:(self.numberOfRowsOnScreen + 1) withNewline:NO];
    }
}

- (void)fillCurrentScreenWithSpacesUpToCursor;
{
    [self createBlankLinesUpToCursor];

    for (NSInteger i = self.cursorPosition.y - 1; i > 0; i--) {
        if ([self numberOfCharactersInScrollRow:i] == TERM_WIDTH || [self isScrollRowTerminatedInNewline:i]) {
            break;
        }

        [self setScrollRow:i hasNewline:YES];
    }

    NSInteger numberOfSpacesToInsert = MAX(self.cursorPosition.x - [self numberOfCharactersInScrollRow:self.cursorPosition.y] - 1, 0);
    if (numberOfSpacesToInsert > 0) {
        [self replaceCharactersAtScrollRow:self.cursorPosition.y scrollColumn:(self.cursorPosition.x - numberOfSpacesToInsert) withString:[@"" stringByPaddingToLength:numberOfSpacesToInsert withString:@" " startingAtIndex:0]];
    }
}

- (void)incrementRowOffset;
{
    self.hasUsedWholeScreen = self.hasUsedWholeScreen || (self.characterOffsetToScreen >= TERM_HEIGHT * TERM_WIDTH);
    self.characterOffsetToScreen += [self numberOfCharactersInScrollRow:1];
    if ([self isScrollRowTerminatedInNewline:1]) {
        self.characterOffsetToScreen++;
    }

    [self.characterCountsOnVisibleRows removeObjectAtIndex:0];
    [self.scrollRowHasNewline removeObjectAtIndex:0];
}

- (NSInteger)characterOffsetUpToScrollRow:(NSInteger)row;
{
    NSInteger offset = self.characterOffsetToScreen;
    for (NSInteger i = 1; i < row; i++) {
        offset += [self numberOfCharactersInScrollRow:i];
        if ([self isScrollRowTerminatedInNewline:i]) {
            offset++;
        }
    }

    return offset;
}

- (void)checkIfExceededLastLineAndObeyScrollMargin:(BOOL)obeyScrollMargin;
{
    if (obeyScrollMargin && (self.cursorPosition.y > self.scrollMarginBottom)) {
        NSAssert(self.cursorPosition.y == (self.scrollMarginBottom + 1), @"Cursor should only be one line below the bottom margin");

        if (self.scrollMarginTop > 1) {
            [self removeLineAtScrollRow:self.scrollMarginTop];
            [self insertBlankLineAtScrollRow:self.scrollMarginBottom withNewline:NO];
        } else {
            [self incrementRowOffset];
            [self insertBlankLineAtScrollRow:self.scrollMarginBottom withNewline:NO];
        }

        self.cursorPosition = MMPositionMake(self.cursorPosition.x, self.cursorPosition.y - 1);
    } else if (self.cursorPosition.y > TERM_HEIGHT) {
        NSAssert(self.cursorPosition.y == (TERM_HEIGHT + 1), @"Cursor should only be one line from the bottom");

        [self incrementRowOffset];
        [self insertBlankLineAtScrollRow:TERM_HEIGHT withNewline:NO];

        self.cursorPosition = MMPositionMake(self.cursorPosition.x, self.cursorPosition.y - 1);
    }
}

- (void)setScrollMarginTop:(NSUInteger)top ScrollMarginBottom:(NSUInteger)bottom;
{
    // TODO: Handle [1;1r -> [1;2r and test.

    top = MIN(MAX(top, 1), TERM_HEIGHT - 1);
    bottom = MAX(MIN(bottom, TERM_HEIGHT), top + 1);

    self.scrollMarginBottom = bottom;
    self.scrollMarginTop = top;
}

- (NSInteger)cursorPositionByCharacters;
{
    NSInteger cursorPosition = self.characterOffsetToScreen;
    for (NSInteger i = 1; i < MIN(self.cursorPosition.y, self.numberOfRowsOnScreen); i++) {
        cursorPosition += [self numberOfCharactersInScrollRow:i];
        if ([self isScrollRowTerminatedInNewline:i]) {
            cursorPosition++;
        }
    }

    cursorPosition = cursorPosition + (self.numberOfRowsOnScreen >= self.cursorPosition.y ? MIN(self.cursorPosition.x - 1, [self numberOfCharactersInScrollRow:self.cursorPosition.y]) : 0);

    return cursorPosition;
}

- (NSMutableAttributedString *)currentANSIDisplay;
{
    return [self.displayTextStorage copy];
}

- (void)handleEscapeSequence:(NSString *)escapeSequence;
{

    MMANSIAction *action = nil;
    unichar escapeCode;
    if ([escapeSequence characterAtIndex:1] == '[') {
        escapeCode = [escapeSequence characterAtIndex:([escapeSequence length] - 1)];
        NSArray *items = [[escapeSequence substringWithRange:NSMakeRange(2, [escapeSequence length] - 3)] componentsSeparatedByString:@";"];
        if (escapeCode == 'A') {
            action = [[MMMoveCursorUp alloc] initWithArguments:items];
        } else if (escapeCode == 'B') {
            action = [[MMMoveCursorDown alloc] initWithArguments:items];
        } else if (escapeCode == 'C') {
            action = [[MMMoveCursorForward alloc] initWithArguments:items];
        } else if (escapeCode == 'D') {
            action = [[MMMoveCursorBackward alloc] initWithArguments:items];
        } else if (escapeCode == 'G') {
            action = [[MMMoveCursorPosition alloc] initWithArguments:[@[@(self.cursorPosition.y)] arrayByAddingObjectsFromArray:items]];
        } else if (escapeCode == 'H' || escapeCode == 'f') {
            action = [[MMMoveCursorPosition alloc] initWithArguments:items];
        } else if (escapeCode == 'K') {
            action = [[MMClearUntilEndOfLine alloc] initWithArguments:items];
        } else if (escapeCode == 'J') {
            action = [[MMClearScreen alloc] initWithArguments:items];
        } else if (escapeCode == 'L') {
            action = [[MMInsertBlankLines alloc] initWithArguments:items];
        } else if (escapeCode == 'M') {
            action = [[MMDeleteLines alloc] initWithArguments:items];
        } else if (escapeCode == 'P') {
            action = [[MMDeleteCharacters alloc] initWithArguments:items];
        } else if (escapeCode == 'c') {
            [self handleUserInput:@"\033[?1;2c"];
        } else if (escapeCode == 'd') {
            // TODO: Make this determine the second argument at evaluation-time.
            id firstArg = items.count >= 1 ? items[0] : MMMoveCursorPosition.defaultArguments[0];
            action = [[MMMoveCursorPosition alloc] initWithArguments:@[firstArg, @(self.cursorPosition.x)]];
        } else if ([escapeSequence isEqualToString:@"\033[?1h"]) {
            self.cursorKeyMode = YES;
        } else if ([escapeSequence isEqualToString:@"\033[?1l"]) {
            self.cursorKeyMode = NO;
        } else if ([escapeSequence isEqualToString:@"\033[?6h"]) {
            self.originMode = YES;
        } else if ([escapeSequence isEqualToString:@"\033[?6l"]) {
            self.originMode = NO;
        } else if ([escapeSequence isEqualToString:@"\033[?7h"]) {
            self.autowrapMode = YES;
        } else if ([escapeSequence isEqualToString:@"\033[?7l"]) {
            self.autowrapMode = NO;
        } else if (escapeCode == 'm') {
            [self handleCharacterAttributes:items];
        } else if (escapeCode == 'r') {
            NSUInteger bottom = [items count] >= 2 ? [items[1] intValue] : TERM_HEIGHT;
            NSUInteger top = [items count] >= 1 ? [items[0] intValue] : 1;
            [self setScrollMarginTop:top ScrollMarginBottom:bottom];
        } else {
            MMLog(@"Unhandled escape sequence: %@", escapeSequence);
        }
    } else {
        escapeCode = [escapeSequence characterAtIndex:1];
        // This covers all escape sequences that do not start with '['.
        if (escapeCode == 'D') {
            action = [[MMIndex alloc] init];
        } else if (escapeCode == 'E') {
            action = [MMNextLine new];
        } else if (escapeCode == 'M') {
            action = [[MMReverseIndex alloc] init];
        } else if (escapeCode == '#' && [escapeSequence characterAtIndex:2] == '8') {
            action = [MMDecAlignmentTest new];
        } else {
            MMLog(@"Unhandled early escape sequence: %@", escapeSequence);
        }
    }

    if (action) {
        action.delegate = self;
        [action do];
    }
}

- (void)handleCharacterAttributes:(NSArray *)items;
{
    if (items.count == 0) {
        items = @[@0];
    }

    for (NSNumber *argument in items) {
        switch ([argument integerValue]) {
            case 0:
                [self.characterAttributes removeAllObjects];
                self.characterAttributes[NSFontAttributeName] = [NSFont userFixedPitchFontOfSize:[NSFont systemFontSize]];
                break;
            case 1:
                self.characterAttributes[NSFontAttributeName] = [[NSFontManager sharedFontManager] convertFont:self.characterAttributes[NSFontAttributeName] toHaveTrait:NSBoldFontMask];
                break;
            case 4:
                self.characterAttributes[NSUnderlineStyleAttributeName] = @(NSUnderlineStyleSingle);
                break;
            case 22:
                self.characterAttributes[NSFontAttributeName] = [[NSFontManager sharedFontManager] convertFont:self.characterAttributes[NSFontAttributeName] toHaveTrait:NSUnboldFontMask];
                break;
            case 24:
                [self.characterAttributes removeObjectForKey:NSUnderlineStyleAttributeName];
                break;
            case 30:
                self.characterAttributes[NSForegroundColorAttributeName] = [NSColor blackColor];
                break;
            case 31:
                self.characterAttributes[NSForegroundColorAttributeName] = [NSColor colorWithCalibratedHue:0.0 saturation:1.0 brightness:0.6 alpha:1.0];
                break;
            case 32:
                self.characterAttributes[NSForegroundColorAttributeName] = [NSColor colorWithCalibratedHue:(120.0 / 360.0) saturation:1.0 brightness:0.65 alpha:1.0];
                break;
            case 33:
                self.characterAttributes[NSForegroundColorAttributeName] = [NSColor colorWithCalibratedHue:(60.0 / 360.0) saturation:1.0 brightness:0.5 alpha:1.0];
                break;
            case 34:
                self.characterAttributes[NSForegroundColorAttributeName] = [NSColor colorWithCalibratedHue:(240.0 / 360.0) saturation:1.0 brightness:0.7 alpha:1.0];
                break;
            case 35:
                self.characterAttributes[NSForegroundColorAttributeName] = [NSColor colorWithCalibratedHue:(300.0 / 360.0) saturation:1.0 brightness:0.7 alpha:1.0];
                break;
            case 36:
                self.characterAttributes[NSForegroundColorAttributeName] = [NSColor colorWithCalibratedHue:(184.0 / 360.0) saturation:1.0 brightness:0.7 alpha:1.0];
                break;
            case 37:
                self.characterAttributes[NSForegroundColorAttributeName] = [NSColor colorWithCalibratedHue:(184.0 / 360.0) saturation:0.0 brightness:0.75 alpha:1.0];
                break;
            case 40:
                self.characterAttributes[NSBackgroundColorAttributeName] = [NSColor blackColor];
                break;
            case 41:
                self.characterAttributes[NSBackgroundColorAttributeName] = [NSColor colorWithCalibratedHue:0.0 saturation:1.0 brightness:0.6 alpha:1.0];
                break;
            case 42:
                self.characterAttributes[NSBackgroundColorAttributeName] = [NSColor colorWithCalibratedHue:(120.0 / 360.0) saturation:1.0 brightness:0.65 alpha:1.0];
                break;
            case 43:
                self.characterAttributes[NSBackgroundColorAttributeName] = [NSColor colorWithCalibratedHue:(60.0 / 360.0) saturation:1.0 brightness:0.5 alpha:1.0];
                break;
            case 44:
                self.characterAttributes[NSBackgroundColorAttributeName] = [NSColor colorWithCalibratedHue:(240.0 / 360.0) saturation:1.0 brightness:0.7 alpha:1.0];
                break;
            case 45:
                self.characterAttributes[NSBackgroundColorAttributeName] = [NSColor colorWithCalibratedHue:(300.0 / 360.0) saturation:1.0 brightness:0.7 alpha:1.0];
                break;
            case 46:
                self.characterAttributes[NSBackgroundColorAttributeName] = [NSColor colorWithCalibratedHue:(184.0 / 360.0) saturation:1.0 brightness:0.7 alpha:1.0];
                break;
            case 47:
                self.characterAttributes[NSBackgroundColorAttributeName] = [NSColor colorWithCalibratedHue:(184.0 / 360.0) saturation:0.0 brightness:0.75 alpha:1.0];
                break;
        }
    }
}

# pragma mark - MMANSIActionDelegate methods

- (NSInteger)termHeight;
{
    return TERM_HEIGHT;
}

- (NSInteger)termWidth;
{
    return TERM_WIDTH;
}

- (NSInteger)cursorPositionX;
{
    return self.cursorPosition.x;
}

- (NSInteger)cursorPositionY;
{
    return self.cursorPosition.y;
}

- (void)setCursorToX:(NSInteger)x Y:(NSInteger)y;
{
    self.cursorPosition = MMPositionMake(x, y);
}

- (NSInteger)numberOfCharactersInScrollRow:(NSInteger)row;
{
    return [self.characterCountsOnVisibleRows[row - 1] integerValue];
}

- (BOOL)isScrollRowTerminatedInNewline:(NSInteger)row;
{
    return [self.scrollRowHasNewline[row - 1] boolValue];
}

- (BOOL)isCursorInScrollRegion;
{
    return self.cursorPosition.y >= self.scrollMarginTop && self.cursorPosition.y <= self.scrollMarginBottom;
}

- (NSInteger)numberOfRowsOnScreen;
{
    return self.characterCountsOnVisibleRows.count;
}

- (void)replaceCharactersAtScrollRow:(NSInteger)row scrollColumn:(NSInteger)column withString:(NSString *)replacementString;
{
    NSAssert(column + replacementString.length - 1 <= TERM_WIDTH, @"replacementString too large or incorrect column specified");
    NSAttributedString *attributedString = [[NSAttributedString alloc] initWithString:replacementString attributes:self.characterAttributes];
    NSInteger enlargementSize = MAX(0, (column + ((NSInteger)replacementString.length) - 1) - [self numberOfCharactersInScrollRow:row]);
    [self adjustNumberOfCharactersOnScrollRow:row byAmount:enlargementSize];
    [self.displayTextStorage replaceCharactersInRange:NSMakeRange([self characterOffsetUpToScrollRow:row] + column - 1, replacementString.length - enlargementSize) withAttributedString:attributedString];
}

- (void)removeCharactersInScrollRow:(NSInteger)row range:(NSRange)range shiftCharactersAfter:(BOOL)shift;
{
    NSAssert(range.location > 0, @"Range location must be provided in ANSI column form");
    if (range.location > [self numberOfCharactersInScrollRow:row]) {
        return;
    }

    NSInteger numberOfCharactersBeingRemoved = MIN([self numberOfCharactersInScrollRow:row], range.location + range.length - 1) - range.location + 1;
    [self adjustNumberOfCharactersOnScrollRow:row byAmount:(-numberOfCharactersBeingRemoved)];
    [self.displayTextStorage deleteCharactersInRange:NSMakeRange([self characterOffsetUpToScrollRow:row] + range.location - 1, numberOfCharactersBeingRemoved)];
}

- (void)insertBlankLineAtScrollRow:(NSInteger)row withNewline:(BOOL)newline;
{
    NSAssert(self.numberOfRowsOnScreen < TERM_HEIGHT, @"inserting a line would cause more than termHeight lines to be displayed");
    [self.characterCountsOnVisibleRows insertObject:@0 atIndex:(row - 1)];
    [self.scrollRowHasNewline insertObject:@NO atIndex:(row - 1)];
    [self setScrollRow:row hasNewline:newline];
}

- (void)removeLineAtScrollRow:(NSInteger)row;
{
    NSInteger lengthIncludingNewline = ([self isScrollRowTerminatedInNewline:row] ? 1 : 0) + [self numberOfCharactersInScrollRow:row];
    [self.displayTextStorage deleteCharactersInRange:NSMakeRange([self characterOffsetUpToScrollRow:row], lengthIncludingNewline)];
    [self.characterCountsOnVisibleRows removeObjectAtIndex:(row - 1)];
    [self.scrollRowHasNewline removeObjectAtIndex:(row - 1)];
}

- (void)setScrollRow:(NSInteger)row hasNewline:(BOOL)hasNewline;
{
    if ([self isScrollRowTerminatedInNewline:row] == hasNewline) {
        return;
    }

    if (hasNewline) {
        [self.displayTextStorage insertAttributedString:[[NSAttributedString alloc] initWithString:@"\n"] atIndex:[self characterOffsetUpToScrollRow:(row + 1)]];
    } else {
        [self.displayTextStorage deleteCharactersInRange:NSMakeRange([self characterOffsetUpToScrollRow:(row + 1)] - 1, 1)];
    }
    [self.scrollRowHasNewline setObject:@(hasNewline) atIndexedSubscript:(row - 1)];
}

# pragma mark - NSCoding

- (void)encodeWithCoder:(NSCoder *)coder;
{
    [coder encodeObject:self.startedAt forKey:MMSelfKey(startedAt)];
    [coder encodeObject:self.finishedAt forKey:MMSelfKey(finishedAt)];
    [coder encodeObject:self.displayTextStorage forKey:MMSelfKey(displayTextStorage)];
    [coder encodeObject:self.command forKey:MMSelfKey(command)];
    [coder encodeInteger:self.cursorPositionByCharacters forKey:MMSelfKey(cursorPositionByCharacters)];
    [coder encodeBool:self.hasUsedWholeScreen forKey:MMSelfKey(hasUsedWholeScreen)];
    [coder encodeBool:self.shellCommand forKey:MMSelfKey(shellCommand)];
    [coder encodeBool:self.shellCommandSuccessful forKey:MMSelfKey(shellCommandSuccessful)];
    [coder encodeObject:self.shellCommandAttachment forKey:MMSelfKey(shellCommandAttachment)];
}

- (id)initWithCoder:(NSCoder *)decoder;
{
    self = [self init];
    if (!self) {
        return nil;
    }

    self.startedAt = [decoder decodeObjectForKey:MMSelfKey(startedAt)];
    self.finishedAt = [decoder decodeObjectForKey:MMSelfKey(finishedAt)];
    self.displayTextStorage = [decoder decodeObjectForKey:MMSelfKey(displayTextStorage)];
    self.command = [decoder decodeObjectForKey:MMSelfKey(command)];
    self.characterOffsetToScreen = [decoder decodeIntegerForKey:MMSelfKey(cursorPositionByCharacters)];
    self.hasUsedWholeScreen = [decoder decodeBoolForKey:MMSelfKey(hasUsedWholeScreen)];
    self.shellCommand = [decoder decodeBoolForKey:MMSelfKey(shellCommand)];
    self.shellCommandSuccessful = [decoder decodeBoolForKey:MMSelfKey(shellCommandSuccessful)];
    self.shellCommandAttachment = [decoder decodeObjectForKey:MMSelfKey(shellCommandAttachment)];

    return self;
}

@end
