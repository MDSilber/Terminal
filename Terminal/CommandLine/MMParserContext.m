//
//  MMParserContext.m
//  Terminal
//
//  Created by Mehdi Mulani on 5/7/13.
//  Copyright (c) 2013 Mehdi Mulani. All rights reserved.
//

#import "MMParserContext.h"

@implementation MMParserContext

NSMutableDictionary *_parsers = nil;
NSMutableArray *_storedObjects = nil;

+ (void)initialize;
{
    _parsers = [NSMutableDictionary dictionary];
    _storedObjects = [NSMutableArray array];
}

+ (MMParserContext *)parserForContext:(MMParserCtx *)context;
{
    return [_parsers objectForKey:[NSValue valueWithPointer:context]];
}

+ (void)storeObject:(id)object;
{
    [_storedObjects addObject:object];
}

- (id)init;
{
    self = [super init];
    if (!self) {
        return nil;
    }

    self.scanner = (MMParserCtx *)malloc(sizeof(MMParserCtx));
    [_parsers setObject:self forKey:[NSValue valueWithPointer:self.scanner]];
    [self initScanner];

    return self;
}

- (void)dealloc;
{
    [_parsers removeObjectForKey:[NSValue valueWithPointer:self.scanner]];
    [self deallocScanner];
    free(self.scanner);
    self.scanner = nil;
}

- (void)initScanner;
{
    yylex_init(&(self.scanner->scanner));
	yyset_extra(self.scanner,self.scanner->scanner);
	self.scanner->error_text = nil;
	self.scanner->error_line = -1;
}

- (void)deallocScanner;
{
    yylex_destroy(self.scanner->scanner);
}

- (int)inputToBuffer:(char *)buffer maxBytesToRead:(size_t)maxBytesToRead;
{
    if (self.stream.streamStatus == NSStreamStatusAtEnd ||
        self.stream.streamStatus == NSStreamStatusClosed ||
        self.stream.streamStatus == NSStreamStatusError ||
        self.stream.streamStatus == NSStreamStatusNotOpen) {
        return 0;
    }

    NSInteger bytesRead = [self.stream read:(uint8_t *)buffer maxLength:maxBytesToRead];
    if (bytesRead < 0) {
        return 0;
    }

    return (int)bytesRead;
}

- (id)parseString:(NSString *)commandLineInput;
{
    id result;
    NSData *data = [commandLineInput dataUsingEncoding:NSUTF8StringEncoding];
    self.stream = [NSInputStream inputStreamWithData:data];
    [self.stream open];
    self.scanner->result = nil;
    if (yyparse(self.scanner)) {
        // TODO: Error handling.
        return nil;
    }
    result = self.scanner->result;
    _storedObjects = [NSMutableArray array];
    self.scanner->result = nil;
    [self.stream close];
    self.stream = nil;

    return result;
}

@end