//
//  MMTerminalConnection.m
//  Terminal
//
//  Created by Mehdi Mulani on 5/8/13.
//  Copyright (c) 2013 Mehdi Mulani. All rights reserved.
//

#include <termios.h>
#include <util.h>
#include <sys/wait.h>

#import "MMTerminalConnection.h"
#import "MMTerminalWindowController.h"
#import "MMShared.h"
#import "MMCommandLineArgumentsParser.h"

#define CTRLKEY(c)   ((c)-'A'+1)

@interface MMTerminalConnection ()

@property NSConnection *connectionToSelf;

@end

@implementation MMTerminalConnection

- (id)initWithIdentifier:(NSInteger)identifier;
{
    self = [self init];
    if (!self) {
        return nil;
    }

    self.identifier = identifier;
    
    return self;
}

- (void)createTerminalWindow;
{
    self.terminalWindow = [[MMTerminalWindowController alloc] initWithTerminalConnection:self];
    [self.terminalWindow showWindow:nil];

    self.connectionToSelf = [NSConnection serviceConnectionWithName:[ConnectionTerminalName stringByAppendingFormat:@".%ld", (long)self.identifier] rootObject:self];

    [NSThread detachNewThreadSelector:@selector(startShell) toTarget:self withObject:nil];
}

- (void)runCommands:(NSString *)commandsText;
{
    // TODO: Support multiple commands.
    NSArray *commands = [MMCommandLineArgumentsParser parseCommandsFromCommandLine:commandsText];

    if (commands.count > 1) {
        MMLog(@"Discarded all commands past the first in: %@", commandsText);
    }

    NSProxy *proxy = [[NSConnection connectionWithRegisteredName:[ConnectionShellName stringByAppendingFormat:@".%ld", (long)self.identifier] host:nil] rootProxy];
    [proxy performSelector:@selector(executeCommand:) withObject:commands[0]];
    [self.terminalWindow setRunning:YES];
}

- (void)startShell;
{
    NSProxy *proxy = [self.connectionToSelf rootProxy];

    struct termios term;
    struct winsize win;

    memset(&term, 0, sizeof(struct termios));
    memset(&win, 0, sizeof(struct winsize));

	term.c_iflag = ICRNL | IXON | IXANY | IMAXBEL | BRKINT;
	term.c_oflag = OPOST | ONLCR;
	term.c_cflag = CREAD | CS8 | HUPCL;
	term.c_lflag = ICANON | ISIG | IEXTEN | ECHO | ECHOE | ECHOK | ECHOKE | ECHOCTL;

	term.c_cc[VEOF]	  = CTRLKEY('D');
	term.c_cc[VEOL]	  = -1;
	term.c_cc[VEOL2]	  = -1;
	term.c_cc[VERASE]	  = 0x7f;	// DEL
	term.c_cc[VWERASE]   = CTRLKEY('W');
	term.c_cc[VKILL]	  = CTRLKEY('U');
	term.c_cc[VREPRINT]  = CTRLKEY('R');
	term.c_cc[VINTR]	  = CTRLKEY('C');
	term.c_cc[VQUIT]	  = 0x1c;	// Control+backslash
	term.c_cc[VSUSP]	  = CTRLKEY('Z');
	term.c_cc[VDSUSP]	  = CTRLKEY('Y');
	term.c_cc[VSTART]	  = CTRLKEY('Q');
	term.c_cc[VSTOP]	  = CTRLKEY('S');
	term.c_cc[VLNEXT]	  = -1;
	term.c_cc[VDISCARD]  = -1;
	term.c_cc[VMIN]	  = 1;
	term.c_cc[VTIME]	  = 0;
	term.c_cc[VSTATUS]   = -1;

	term.c_ispeed = B38400;
	term.c_ospeed = B38400;

	win.ws_row = 24;
	win.ws_col = 80;
	win.ws_xpixel = 0;
	win.ws_ypixel = 0;

    char ttyname[PATH_MAX];
    pid_t pid;
    {
        int fd;
        pid = forkpty(&fd, ttyname, &term, &win);
        self.fd = fd;
    }

    if (pid == (pid_t)0) {
        // Running as the shell.
        // These pipes are written from the shell's point-of-view.
        // That is, the shell intends to write into the writepipe, and read from the readpipe.

        NSFileManager *fileManager = [[NSFileManager alloc] init];

        const char *args[3];
        args[0] = [[[fileManager currentDirectoryPath] stringByAppendingPathComponent:@"Shell"] cStringUsingEncoding:NSUTF8StringEncoding];
        args[1] = ((NSString *)[NSString stringWithFormat:@"%ld", (long)self.identifier]).UTF8String;
        args[2] = NULL;
        NSLog(@"Starting %s", args[0]);
        execv(args[0], args);

        NSLog(@"Reached bad part. %s", args[0]);

        exit(1);
    }

    NSLog(@"Started with pid %d", pid);

    NSLog(@"TTY started: %@ with fd %d", [NSString stringWithCString:ttyname encoding:NSUTF8StringEncoding], self.fd);

    fd_set rfds;
    fd_set wfds;
    fd_set efds;

    while (true) {
        FD_ZERO(&rfds);
        FD_ZERO(&wfds);
        FD_ZERO(&efds);

        FD_SET(self.fd, &rfds);
        int result = select(self.fd + 1, &rfds, &wfds, &efds, nil);

        if (FD_ISSET(self.fd, &rfds)) {
            // Mac OS X caps read() to 1024 bytes (for some reason), we expect that 4KiB is the most that will be sent in one read.
            NSMutableData *data = [NSMutableData dataWithLength:1024 * 4];
            ssize_t totalBytesRead = 0;
            for (NSUInteger i = 0; i < 4; i++) {
                ssize_t bytesRead = read(self.fd, [data mutableBytes] + totalBytesRead, 1024);

                if (bytesRead < 0) {
                    if (errno != EAGAIN && errno != EINTR) {
                        NSLog(@"Serious error.");
                        return;
                    }

                    if (totalBytesRead == 1024) {
                        MMLog(@"Warning: only read 1024 bytes.");
                    }
                    bytesRead = 0;
                }

                totalBytesRead += bytesRead;

                if (bytesRead < 1024) {
                    break;
                }
            }

            if (totalBytesRead == 0) {
                int status;
                waitpid(pid, &status, WNOHANG);
                if (WIFEXITED(status) || WIFSIGNALED(status)) {
                    NSLog(@"Exited?");
                    break;
                }

                continue;
            }

            [data setLength:totalBytesRead];
            NSString *readData = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
            [proxy performSelector:@selector(handleOutput:) withObject:readData];
        }
        
        if (FD_ISSET(self.fd, &wfds)) {
            NSLog(@"Gotta write");
        }
    }
    
    close(self.fd);
    self.fd = -1;
}

- (void)handleTerminalInput:(NSString *)input;
{
    if (self.terminalWindow.running && [input length]) {
        const char *typed = [input cStringUsingEncoding:NSUTF8StringEncoding];
        write(self.fd, typed, [input length]);
    }
}

- (void)handleOutput:(NSString *)output;
{
    [self.terminalWindow handleOutput:output];
}

- (void)processFinished;
{
    NSLog(@"Process finished");

    [self.terminalWindow processFinished];
}

- (void)directoryChangedTo:(NSString *)newPath;
{
    [self.terminalWindow directoryChangedTo:newPath];
}

@end