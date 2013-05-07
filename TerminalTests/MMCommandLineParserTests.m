//
//  MMCommandLineParserTests.m
//  Terminal
//
//  Created by Mehdi Mulani on 5/7/13.
//  Copyright (c) 2013 Mehdi Mulani. All rights reserved.
//

#import "MMCommandLineParserTests.h"
#import "MMParserContext.h"

@implementation MMCommandLineParserTests

#define CompareInputAgainstExpectedParsedOutput(input, output) \
do {\
    id result = [[[MMParserContext alloc] init] parseString:input]; \
    STAssertEqualObjects(result, output, @"Compared parser output to provided output."); \
} while (0)

- (void)testCommandSplitting;
{
    CompareInputAgainstExpectedParsedOutput(@"echo", @[@[@"echo"]]);
    CompareInputAgainstExpectedParsedOutput(@";echo", (@[@[], @[@"echo"]]));
    CompareInputAgainstExpectedParsedOutput(@";echo;", (@[@[], @[@"echo"]]));
    CompareInputAgainstExpectedParsedOutput(@"ec\"ho\"", @[@[@"ec\"ho\""]]);
    CompareInputAgainstExpectedParsedOutput(@"echo 1 2 3; test", (@[@[@"echo", @"1", @"2", @"3"], @[@"test"]]));
    CompareInputAgainstExpectedParsedOutput(@"cp \"test file\" a.out", (@[@[@"cp", @"\"test file\"", @"a.out"]]));
}

@end