/*
 * Copyright (c) 2008, 2009, 2010, 2011, 2012
 *   Jonathan Schleifer <js@webkeks.org>
 *
 * All rights reserved.
 *
 * This file is part of ObjFW. It may be distributed under the terms of the
 * Q Public License 1.0, which can be found in the file LICENSE.QPL included in
 * the packaging of this file.
 *
 * Alternatively, it may be distributed under the terms of the GNU General
 * Public License, either version 2 or 3, which can be found in the file
 * LICENSE.GPLv2 or LICENSE.GPLv3 respectively included in the packaging of this
 * file.
 */

#include "config.h"

#import "OFRunLoop.h"
#import "OFDictionary.h"
#import "OFThread.h"
#import "OFSortedList.h"
#import "OFTimer.h"
#import "OFDate.h"

#import "autorelease.h"
#import "macros.h"

static OFRunLoop *mainRunLoop = nil;

@interface OFRunLoop_ReadQueueItem: OFObject
{
@public
	void *buffer;
	size_t length;
	id target;
	SEL selector;
#ifdef OF_HAVE_BLOCKS
	of_stream_async_read_block_t block;
#endif
}
@end

@interface OFRunLoop_ExactReadQueueItem: OFObject
{
@public
	void *buffer;
	size_t exactLength, readLength;
	id target;
	SEL selector;
#ifdef OF_HAVE_BLOCKS
	of_stream_async_read_block_t block;
#endif
}
@end

@interface OFRunLoop_ReadLineQueueItem: OFObject
{
@public
	of_string_encoding_t encoding;
	id target;
	SEL selector;
#ifdef OF_HAVE_BLOCKS
	of_stream_async_read_line_block_t block;
#endif
}
@end

@interface OFRunLoop_AcceptQueueItem: OFObject
{
@public
	id target;
	SEL selector;
#ifdef OF_HAVE_BLOCKS
	of_tcpsocket_async_accept_block_t block;
#endif
}
@end

@implementation OFRunLoop_ReadQueueItem
- (void)dealloc
{
	[target release];
#ifdef OF_HAVE_BLOCKS
	[block release];
#endif

	[super dealloc];
}
@end

@implementation OFRunLoop_ExactReadQueueItem
- (void)dealloc
{
	[target release];
#ifdef OF_HAVE_BLOCKS
	[block release];
#endif

	[super dealloc];
}
@end

@implementation OFRunLoop_ReadLineQueueItem
- (void)dealloc
{
	[target release];
#ifdef OF_HAVE_BLOCKS
	[block release];
#endif

	[super dealloc];
}
@end

@implementation OFRunLoop_AcceptQueueItem
- (void)dealloc
{
	[target release];
#ifdef OF_HAVE_BLOCKS
	[block release];
#endif

	[super dealloc];
}
@end

@implementation OFRunLoop
+ (OFRunLoop*)mainRunLoop
{
	return [[mainRunLoop retain] autorelease];
}

+ (OFRunLoop*)currentRunLoop
{
	return [[OFThread currentThread] runLoop];
}

+ (void)OF_setMainRunLoop
{
	void *pool = objc_autoreleasePoolPush();
	mainRunLoop = [[self currentRunLoop] retain];
	objc_autoreleasePoolPop(pool);
}

#define ADD(type, code)							\
	void *pool = objc_autoreleasePoolPush();			\
	OFRunLoop *runLoop = [self currentRunLoop];			\
	OFList *queue = [runLoop->readQueues objectForKey: stream];	\
	type *queueItem;						\
									\
	if (queue == nil) {						\
		queue = [OFList list];					\
		[runLoop->readQueues setObject: queue			\
					forKey: stream];		\
	}								\
									\
	if ([queue count] == 0)						\
		[runLoop->streamObserver addStreamForReading: stream];	\
									\
	queueItem = [[[type alloc] init] autorelease];			\
	code								\
	[queue appendObject: queueItem];				\
									\
	objc_autoreleasePoolPop(pool);

+ (void)OF_addAsyncReadForStream: (OFStream*)stream
			  buffer: (void*)buffer
			  length: (size_t)length
			  target: (id)target
			selector: (SEL)selector
{
	ADD(OFRunLoop_ReadQueueItem, {
		queueItem->buffer = buffer;
		queueItem->length = length;
		queueItem->target = [target retain];
		queueItem->selector = selector;
	})
}

+ (void)OF_addAsyncReadForStream: (OFStream*)stream
			  buffer: (void*)buffer
		     exactLength: (size_t)exactLength
			  target: (id)target
			selector: (SEL)selector
{
	ADD(OFRunLoop_ExactReadQueueItem, {
		queueItem->buffer = buffer;
		queueItem->exactLength = exactLength;
		queueItem->target = [target retain];
		queueItem->selector = selector;
	})
}

+ (void)OF_addAsyncReadLineForStream: (OFStream*)stream
			    encoding: (of_string_encoding_t)encoding
			      target: (id)target
			    selector: (SEL)selector
{
	ADD(OFRunLoop_ReadLineQueueItem, {
		queueItem->encoding = encoding;
		queueItem->target = [target retain];
		queueItem->selector = selector;
	})
}

+ (void)OF_addAsyncAcceptForTCPSocket: (OFTCPSocket*)stream
			       target: (id)target
			     selector: (SEL)selector
{
	ADD(OFRunLoop_AcceptQueueItem, {
		queueItem->target = [target retain];
		queueItem->selector = selector;
	})
}

#ifdef OF_HAVE_BLOCKS
+ (void)OF_addAsyncReadForStream: (OFStream*)stream
			  buffer: (void*)buffer
			  length: (size_t)length
			   block: (of_stream_async_read_block_t)block
{
	ADD(OFRunLoop_ReadQueueItem, {
		queueItem->buffer = buffer;
		queueItem->length = length;
		queueItem->block = [block copy];
	})
}

+ (void)OF_addAsyncReadForStream: (OFStream*)stream
			  buffer: (void*)buffer
		     exactLength: (size_t)exactLength
			   block: (of_stream_async_read_block_t)block
{
	ADD(OFRunLoop_ExactReadQueueItem, {
		queueItem->buffer = buffer;
		queueItem->exactLength = exactLength;
		queueItem->block = [block copy];
	})
}

+ (void)OF_addAsyncReadLineForStream: (OFStream*)stream
			    encoding: (of_string_encoding_t)encoding
			       block: (of_stream_async_read_line_block_t)block
{
	ADD(OFRunLoop_ReadLineQueueItem, {
		queueItem->encoding = encoding;
		queueItem->block = [block copy];
	})
}

+ (void)OF_addAsyncAcceptForTCPSocket: (OFTCPSocket*)stream
				block: (of_tcpsocket_async_accept_block_t)block
{
	ADD(OFRunLoop_AcceptQueueItem, {
		queueItem->block = [block copy];
	})
}
#endif

#undef ADD

- init
{
	self = [super init];

	@try {
		timersQueue = [[OFSortedList alloc] init];

		streamObserver = [[OFStreamObserver alloc] init];
		[streamObserver setDelegate: self];

		readQueues = [[OFMutableDictionary alloc] init];
	} @catch (id e) {
		[self release];
		@throw e;
	}

	return self;
}

- (void)dealloc
{
	[timersQueue release];
	[streamObserver release];
	[readQueues release];

	[super dealloc];
}

- (void)addTimer: (OFTimer*)timer
{
	@synchronized (timersQueue) {
		[timersQueue addObject: timer];
	}
	[streamObserver cancel];
}

- (void)streamIsReadyForReading: (OFStream*)stream
{
	OFList *queue = [readQueues objectForKey: stream];
	of_list_object_t *listObject;

	OF_ENSURE(queue != nil);

	listObject = [queue firstListObject];

	if ([listObject->object isKindOfClass:
	    [OFRunLoop_ReadQueueItem class]]) {
		OFRunLoop_ReadQueueItem *queueItem = listObject->object;
		size_t length = [stream readIntoBuffer: queueItem->buffer
						length: queueItem->length];

#ifdef OF_HAVE_BLOCKS
		if (queueItem->block != NULL) {
			if (!queueItem->block(stream, queueItem->buffer,
				length)) {
				[queue removeListObject: listObject];

				if ([queue count] == 0) {
					[streamObserver
					    removeStreamForReading: stream];
					[readQueues removeObjectForKey: stream];
				}
			}
		} else {
#endif
			BOOL (*func)(id, SEL, OFStream*, void*, size_t) =
			    (BOOL(*)(id, SEL, OFStream*, void*, size_t))
			    [queueItem->target methodForSelector:
			    queueItem->selector];

			if (!func(queueItem->target, queueItem->selector,
			    stream, queueItem->buffer, length)) {
				[queue removeListObject: listObject];

				if ([queue count] == 0) {
					[streamObserver
					    removeStreamForReading: stream];
					[readQueues removeObjectForKey: stream];
				}
			}
#ifdef OF_HAVE_BLOCKS
		}
#endif
	} else if ([listObject->object isKindOfClass:
	    [OFRunLoop_ExactReadQueueItem class]]) {
		OFRunLoop_ExactReadQueueItem *queueItem = listObject->object;
		size_t length = [stream
		    readIntoBuffer: (char*)queueItem->buffer +
				    queueItem->readLength
			    length: queueItem->exactLength -
				    queueItem->readLength];

		queueItem->readLength += length;
		if (queueItem->readLength == queueItem->exactLength ||
		    [stream isAtEndOfStream]) {
#ifdef OF_HAVE_BLOCKS
			if (queueItem->block != NULL) {
				if (queueItem->block(stream, queueItem->buffer,
				    queueItem->readLength))
					queueItem->readLength = 0;
				else {
					[queue removeListObject: listObject];

					if ([queue count] == 0) {
						[streamObserver
						    removeStreamForReading:
						    stream];
						[readQueues
						    removeObjectForKey: stream];
					}
				}
			} else {
#endif
				BOOL (*func)(id, SEL, OFStream*, void*,
				    size_t) = (BOOL(*)(id, SEL, OFStream*,
				    void*, size_t))[queueItem->target
				    methodForSelector: queueItem->selector];

				if (func(queueItem->target,
				    queueItem->selector, stream,
				    queueItem->buffer, queueItem->readLength))
					queueItem->readLength = 0;
				else {
					[queue removeListObject: listObject];

					if ([queue count] == 0) {
						[streamObserver
						    removeStreamForReading:
						    stream];
						[readQueues
						    removeObjectForKey: stream];
					}
				}
#ifdef OF_HAVE_BLOCKS
			}
#endif
		}
	} else if ([listObject->object isKindOfClass:
	    [OFRunLoop_ReadLineQueueItem class]]) {
		OFRunLoop_ReadLineQueueItem *queueItem = listObject->object;
		OFString *line;

		line = [stream tryReadLineWithEncoding: queueItem->encoding];

		if (line != nil || [stream isAtEndOfStream]) {
#ifdef OF_HAVE_BLOCKS
			if (queueItem->block != NULL) {
				if (!queueItem->block(stream, line)) {
					[queue removeListObject: listObject];

					if ([queue count] == 0) {
						[streamObserver
						    removeStreamForReading:
						    stream];
						[readQueues
						    removeObjectForKey: stream];
					}
				}
			} else {
#endif
				BOOL (*func)(id, SEL, OFStream*, OFString*) =
				    (BOOL(*)(id, SEL, OFStream*, OFString*))
				    [queueItem->target methodForSelector:
				    queueItem->selector];

				if (!func(queueItem->target,
				    queueItem->selector, stream, line)) {
					[queue removeListObject: listObject];

					if ([queue count] == 0) {
						[streamObserver
						    removeStreamForReading:
						    stream];
						[readQueues
						    removeObjectForKey: stream];
					}
				}
#ifdef OF_HAVE_BLOCKS
			}
#endif
		}
	} else if ([listObject->object isKindOfClass:
	    [OFRunLoop_AcceptQueueItem class]]) {
		OFRunLoop_AcceptQueueItem *queueItem = listObject->object;
		OFTCPSocket *newSocket = [(OFTCPSocket*)stream accept];

#ifdef OF_HAVE_BLOCKS
		if (queueItem->block != NULL) {
			if (!queueItem->block((OFTCPSocket*)stream,
			    newSocket)) {
				[queue removeListObject: listObject];

				if ([queue count] == 0) {
					[streamObserver
					    removeStreamForReading: stream];
					[readQueues removeObjectForKey: stream];
				}
			}
		} else {
#endif
			BOOL (*func)(id, SEL, OFTCPSocket*, OFTCPSocket*) =
			    (BOOL(*)(id, SEL, OFTCPSocket*, OFTCPSocket*))
			    [queueItem->target methodForSelector:
			    queueItem->selector];

			if (!func(queueItem->target, queueItem->selector,
			    (OFTCPSocket*)stream, newSocket)) {
				[queue removeListObject: listObject];

				if ([queue count] == 0) {
					[streamObserver
					    removeStreamForReading: stream];
					[readQueues removeObjectForKey: stream];
				}
			}
#ifdef OF_HAVE_BLOCKS
		}
#endif
	} else
		OF_ENSURE(0);
}

- (void)run
{
	for (;;) {
		void *pool = objc_autoreleasePoolPush();
		OFDate *now = [OFDate date];
		OFTimer *timer;
		OFDate *nextTimer;

		@synchronized (timersQueue) {
			of_list_object_t *listObject =
			    [timersQueue firstListObject];

			if (listObject != NULL &&
			    [[listObject->object fireDate] compare: now] !=
			    OF_ORDERED_DESCENDING) {
				timer =
				    [[listObject->object retain] autorelease];

				[timersQueue removeListObject: listObject];
			} else
				timer = nil;
		}

		if ([timer isValid])
			[timer fire];

		@synchronized (timersQueue) {
			nextTimer = [[timersQueue firstObject] fireDate];
		}

		/* Watch for stream events until the next timer is due */
		if (nextTimer != nil) {
			double timeout = [nextTimer timeIntervalSinceNow];

			if (timeout > 0)
				[streamObserver observeWithTimeout: timeout];
		} else {
			/*
			 * No more timers: Just watch for streams until we get
			 * an event. If a timer is added by another thread, it
			 * cancels the observe.
			 */
			[streamObserver observe];
		}

		objc_autoreleasePoolPop(pool);
	}
}
@end
