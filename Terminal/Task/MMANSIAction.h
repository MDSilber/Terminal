//
//  MMANSIAction.h
//  Terminal
//
//  Created by Mehdi Mulani on 5/21/13.
//  Copyright (c) 2013 Mehdi Mulani. All rights reserved.
//

#import <Foundation/Foundation.h>

typedef enum {
    MMDECModeError = 0,
    MMDECModeCursorKey = 1, // DECCKM
    MMDECModeVT52 = 2, // DECANM
    MMDECModeWideColumn = 3, // DECCOLM
    MMDECModeScroll = 4, // DECSCLM
    MMDECModeScreen = 5, // DECSCNM
    MMDECModeOrigin = 6, // DECOM
    MMDECModeAutoWrap = 7, // DECAWM
    MMDECModeAutoRepeat = 8, // DECARM
    MMDECModeCursorVisible = 25, // DECTCEM
    MMDECModeAllowColumnChange = 40,
} MMDECMode;

typedef enum {
    MMANSIModeError = 0,
    MMANSIModeKeyboardAction = 2, // KAM
    MMANSIModeInsert = 4, // IRM
    MMANSIModeEcho = 12, // SRM
    MMANSIModeNewline = 20, // LNM
} MMANSIMode;

@protocol MMANSIActionDelegate;

@interface MMANSIAction : NSObject

@property NSArray *arguments;
@property NSMutableDictionary *data;
@property id<MMANSIActionDelegate> delegate;

+ (NSArray *)defaultArguments;

- (id)initWithArguments:(NSArray *)arguments;

- (id)defaultedArgumentAtIndex:(NSInteger)index;

- (void)setUp;
- (void)tearDown;
- (void)do;

@end

@protocol MMANSIActionDelegate <NSObject>

// These x, y and row positions are all 1-indexed to match with the ANSI positioning system.
// (i.e. 1 <= x <= termWidth and 1 <= row, y <= termHeight)
// The location in NSRange fields are also 1-indexed.

@property (readonly) NSInteger cursorPositionX;
@property (readonly) NSInteger cursorPositionY;
@property (readonly) NSInteger termHeight;
@property (readonly) NSInteger termWidth;
@property (readonly) NSInteger scrollMarginTop;
@property (readonly) NSInteger scrollMarginBottom;

@property BOOL hasUsedWholeScreen;

- (void)setCursorToX:(NSInteger)x Y:(NSInteger)y;
- (NSInteger)numberOfCharactersInScrollRow:(NSInteger)row;
- (NSInteger)numberOfDisplayableCharactersInScrollRow:(NSInteger)row;
- (BOOL)isScrollRowTerminatedInNewline:(NSInteger)row;
- (BOOL)isCursorInScrollRegion;
- (BOOL)isColumnWithinTab:(NSInteger)column inScrollRow:(NSInteger)row;
- (NSInteger)numberOfRowsOnScreen;

- (void)replaceCharactersAtScrollRow:(NSInteger)row scrollColumn:(NSInteger)column withString:(NSString *)replacementString;
- (void)removeCharactersInScrollRow:(NSInteger)row range:(NSRange)range shiftCharactersAfter:(BOOL)shift;

- (void)createBlankLinesUpToCursor;
- (void)insertBlankLineAtScrollRow:(NSInteger)row withNewline:(BOOL)newline;
- (void)removeLineAtScrollRow:(NSInteger)row;
- (void)setScrollRow:(NSInteger)row hasNewline:(BOOL)hasNewline;
- (void)setScrollMarginTop:(NSUInteger)top ScrollMarginBottom:(NSUInteger)bottom;

- (void)addTab:(NSRange)tabRange onScrollRow:(NSInteger)row;

- (void)setANSIMode:(MMANSIMode)ansiMode on:(BOOL)on;
- (BOOL)isANSIModeSet:(MMANSIMode)ansiMode;
- (void)setDECPrivateMode:(MMDECMode)decPrivateMode on:(BOOL)on;
- (BOOL)isDECPrivateModeSet:(MMDECMode)decPrivateMode;

- (void)tryToResizeTerminalForColumns:(NSInteger)columns rows:(NSInteger)rows;

// XXX: Try to remove these or change them to ensure that all calculations for ANSIActions can be done in |setUp|.
- (void)checkIfExceededLastLineAndObeyScrollMargin:(BOOL)obeyScrollMargin;

@end