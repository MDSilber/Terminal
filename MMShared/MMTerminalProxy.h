//
//  MMTerminalProxy.h
//  Terminal
//
//  Created by Mehdi Mulani on 5/30/13.
//  Copyright (c) 2013 Mehdi Mulani. All rights reserved.
//

#import <Foundation/Foundation.h>

#import "MMShellCommands.h"

@protocol MMTerminalProxy <NSObject>

- (void)processFinished;
- (void)directoryChangedTo:(NSString *)newPath;
- (void)shellCommand:(MMShellCommand)command succesful:(BOOL)success attachment:(id)attachment;

@end