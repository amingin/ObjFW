/*
 * Copyright (c) 2008, 2009, 2010, 2011, 2012, 2013
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

#include <stdlib.h>

#import "OFAutoreleasePool.h"
#import "OFArray.h"

#import "macros.h"
#if !defined(OF_HAVE_COMPILER_TLS) && defined(OF_HAVE_THREADS)
# import "threading.h"

# import "OFInitializationFailedException.h"
#endif

#import "autorelease.h"

#define MAX_CACHE_SIZE 0x20

#if defined(OF_HAVE_COMPILER_TLS)
static __thread OFAutoreleasePool **cache = NULL;
#elif defined(OF_HAVE_THREADS)
static of_tlskey_t cacheKey;
#else
static OFAutoreleasePool **cache = NULL;
#endif

@implementation OFAutoreleasePool
#if !defined(OF_HAVE_COMPILER_TLS) && defined(OF_HAVE_THREADS)
+ (void)initialize
{
	if (self != [OFAutoreleasePool class])
		return;

	if (!of_tlskey_new(&cacheKey))
		@throw [OFInitializationFailedException
		    exceptionWithClass: self];
}
#endif

+ alloc
{
#if !defined(OF_HAVE_COMPILER_TLS) && defined(OF_HAVE_THREADS)
	OFAutoreleasePool **cache = of_tlskey_get(cacheKey);
#endif

	if (cache != NULL) {
		unsigned i;

		for (i = 0; i < MAX_CACHE_SIZE; i++) {
			if (cache[i] != NULL) {
				OFAutoreleasePool *pool = cache[i];
				cache[i] = NULL;
				return pool;
			}
		}
	}

	return [super alloc];
}

+ (id)addObject: (id)object
{
	return _objc_rootAutorelease(object);
}

- init
{
	self = [super init];

	@try {
		pool = objc_autoreleasePoolPush();

		_objc_rootAutorelease(self);
	} @catch (id e) {
		[self release];
		@throw e;
	}

	return self;
}

- (void)releaseObjects
{
	ignoreRelease = YES;

	objc_autoreleasePoolPop(pool);
	pool = objc_autoreleasePoolPush();

	_objc_rootAutorelease(self);

	ignoreRelease = NO;
}

- (void)release
{
	[self dealloc];
}

- (void)drain
{
	[self dealloc];
}

- (void)dealloc
{
#if !defined(OF_HAVE_COMPILER_TLS) && defined(OF_HAVE_THREADS)
	OFAutoreleasePool **cache = of_tlskey_get(cacheKey);
#endif

	if (ignoreRelease)
		return;

	ignoreRelease = YES;

	objc_autoreleasePoolPop(pool);

	if (cache == NULL) {
		cache = calloc(sizeof(OFAutoreleasePool*), MAX_CACHE_SIZE);

#if !defined(OF_HAVE_COMPILER_TLS) && defined(OF_HAVE_THREADS)
		if (!of_tlskey_set(cacheKey, cache)) {
			free(cache);
			cache = NULL;
		}
#endif
	}

	if (cache != NULL) {
		unsigned i;

		for (i = 0; i < MAX_CACHE_SIZE; i++) {
			if (cache[i] == NULL) {
				pool = NULL;
				ignoreRelease = NO;

				cache[i] = self;

				return;
			}
		}
	}

	[super dealloc];
}

- retain
{
	[self doesNotRecognizeSelector: _cmd];
	abort();
}

- autorelease
{
	[self doesNotRecognizeSelector: _cmd];
	abort();
}
@end
