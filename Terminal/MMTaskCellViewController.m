//
//  MMTaskCellViewController.m
//  Terminal
//
//  Created by Mehdi Mulani on 2/19/13.
//  Copyright (c) 2013 Mehdi Mulani. All rights reserved.
//

#import "MMTaskCellViewController.h"

@interface MMTaskCellViewController ()

@end

@implementation MMTaskCellViewController

- (id)init;
{
    self = [self initWithNibName:@"MMTaskCellView" bundle:[NSBundle mainBundle]];
    return self;
}

- (id)initWithTask:(MMTask *)task;
{
    self = [self init];
    if (!self) {
        return nil;
    }

    self.task = task;

    return self;
}

- (void)loadView;
{
    [super loadView];

    [self.label setStringValue:[NSString stringWithFormat:@"Ran %@", self.task.command]];

    [self.outputView.layoutManager replaceTextStorage:self.task.output];
    [self.outputView scrollToEndOfDocument:self];

    NSLog(@"Bounds: %@, Frame: %@", NSStringFromSize(self.view.bounds.size), NSStringFromSize(self.view.frame.size));
    NSLog(@"OutputView Bounds: %@, Frame: %@", NSStringFromRect(self.outputView.bounds), NSStringFromRect(self.outputView.frame));
}

- (CGFloat)heightToFitAllOfOutput;
{
    return self.view.frame.size.height - self.outputView.minSize.height + self.outputView.frame.size.height;
}

- (void)scrollToBottom;
{
    [self.outputView scrollToEndOfDocument:self];
}

@end