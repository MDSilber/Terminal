//
//  MMMoveCursor.h
//  Terminal
//
//  Created by Mehdi Mulani on 5/21/13.
//  Copyright (c) 2013 Mehdi Mulani. All rights reserved.
//

#import "MMANSIAction.h"

@interface MMMoveCursorUp : MMANSIAction

@end

@interface MMMoveCursorDown : MMANSIAction

@end

@interface MMMoveCursorForward : MMANSIAction

@end

@interface MMMoveCursorBackward : MMANSIAction

@end

@interface MMBackspace : MMANSIAction

@end

@interface MMMoveCursorPosition : MMANSIAction

@end

@interface MMMoveHorizontalAbsolute : MMANSIAction

@end

@interface MMMoveVerticalAbsolute : MMANSIAction

@end

@interface MMCarriageReturn : MMANSIAction

@end