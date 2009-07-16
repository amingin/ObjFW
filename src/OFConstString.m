/*
 * Copyright (c) 2008 - 2009
 *   Jonathan Schleifer <js@webkeks.org>
 *
 * All rights reserved.
 *
 * This file is part of libobjfw. It may be distributed under the terms of the
 * Q Public License 1.0, which can be found in the file LICENSE included in
 * the packaging of this file.
 */

#include "config.h"

#import "OFConstString.h"
#import "OFExceptions.h"

#ifndef __objc_INCLUDE_GNU
void *_OFConstStringClassReference;
#endif

@implementation OFConstString
#ifndef __objc_INCLUDE_GNU
+ (void)load
{
	objc_setFutureClass((Class)&_OFConstStringClassReference,
	    "OFConstString");
}
#endif

- addMemoryToPool: (void*)ptr
{
	@throw [OFNotImplementedException newWithClass: isa
					   andSelector: _cmd];
}

- (void*)allocMemoryWithSize: (size_t)size
{
	@throw [OFNotImplementedException newWithClass: isa
					   andSelector: _cmd];
}

- (void*)allocMemoryForNItems: (size_t)nitems
                     withSize: (size_t)size
{
	@throw [OFNotImplementedException newWithClass: isa
					   andSelector: _cmd];
}

- (void*)resizeMemory: (void*)ptr
	       toSize: (size_t)size
{
	@throw [OFNotImplementedException newWithClass: isa
					   andSelector: _cmd];
}

- (void*)resizeMemory: (void*)ptr
	     toNItems: (size_t)nitems
	     withSize: (size_t)size
{
	@throw [OFNotImplementedException newWithClass: isa
					   andSelector: _cmd];
}

- freeMemory: (void*)ptr
{
	@throw [OFNotImplementedException newWithClass: isa
					   andSelector: _cmd];
}

- retain
{
	return self;
}

- autorelease
{
	return self;
}

- (size_t)retainCount
{
	return SIZE_MAX;
}

- (void)release
{
}

- (void)dealloc
{
	@throw [OFNotImplementedException newWithClass: isa
					   andSelector: _cmd];
	[super dealloc];	/* Get rid of stupid warning */
}
@end
