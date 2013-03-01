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

#include <string.h>

#import "OFMutableArray_adjacent.h"
#import "OFArray_adjacent.h"
#import "OFDataArray.h"

#import "OFEnumerationMutationException.h"
#import "OFInvalidArgumentException.h"
#import "OFOutOfRangeException.h"

@implementation OFMutableArray_adjacent
+ (void)initialize
{
	if (self == [OFMutableArray_adjacent class])
		[self inheritMethodsFromClass: [OFArray_adjacent class]];
}

- initWithCapacity: (size_t)capacity
{
	self = [super init];

	@try {
		_array = [[OFDataArray alloc] initWithItemSize: sizeof(id)
						      capacity: capacity];
	} @catch (id e) {
		[self release];
		@throw e;
	}

	return self;
}

- (void)addObject: (id)object
{
	if (object == nil)
		@throw [OFInvalidArgumentException
		    exceptionWithClass: [self class]];

	[_array addItem: &object];
	[object retain];

	_mutations++;
}

- (void)insertObject: (id)object
	     atIndex: (size_t)index
{
	if (object == nil)
		@throw [OFInvalidArgumentException
		    exceptionWithClass: [self class]];

	@try {
		[_array insertItem: &object
			   atIndex: index];
	} @catch (OFOutOfRangeException *e) {
		@throw [OFOutOfRangeException exceptionWithClass: [self class]];
	}
	[object retain];

	_mutations++;
}

- (void)insertObjectsFromArray: (OFArray*)array
		       atIndex: (size_t)index
{
	id *objects = [array objects];
	size_t i, count = [array count];

	@try {
		[_array insertItems: objects
			    atIndex: index
			      count: count];
	} @catch (OFOutOfRangeException *e) {
		@throw [OFOutOfRangeException exceptionWithClass: [self class]];
	}

	for (i = 0; i < count; i++)
		[objects[i] retain];

	_mutations++;
}

- (void)replaceObject: (id)oldObject
	   withObject: (id)newObject
{
	id *objects;
	size_t i, count;

	if (oldObject == nil || newObject == nil)
		@throw [OFInvalidArgumentException
		    exceptionWithClass: [self class]];

	objects = [_array items];
	count = [_array count];

	for (i = 0; i < count; i++) {
		if ([objects[i] isEqual: oldObject]) {
			[newObject retain];
			[objects[i] release];
			objects[i] = newObject;

			return;
		}
	}
}

- (void)replaceObjectAtIndex: (size_t)index
		  withObject: (id)object
{
	id *objects;
	id oldObject;

	if (object == nil)
		@throw [OFInvalidArgumentException
		    exceptionWithClass: [self class]];

	objects = [_array items];

	if (index >= [_array count])
		@throw [OFOutOfRangeException exceptionWithClass: [self class]];

	oldObject = objects[index];
	objects[index] = [object retain];
	[oldObject release];
}

- (void)replaceObjectIdenticalTo: (id)oldObject
		      withObject: (id)newObject
{
	id *objects;
	size_t i, count;

	if (oldObject == nil || newObject == nil)
		@throw [OFInvalidArgumentException
		    exceptionWithClass: [self class]];

	objects = [_array items];
	count = [_array count];

	for (i = 0; i < count; i++) {
		if (objects[i] == oldObject) {
			[newObject retain];
			[objects[i] release];
			objects[i] = newObject;

			return;
		}
	}
}

- (void)removeObject: (id)object
{
	id *objects;
	size_t i, count;

	if (object == nil)
		@throw [OFInvalidArgumentException
		    exceptionWithClass: [self class]];

	objects = [_array items];
	count = [_array count];

	for (i = 0; i < count; i++) {
		if ([objects[i] isEqual: object]) {
			object = objects[i];

			[_array removeItemAtIndex: i];
			_mutations++;

			[object release];

			return;
		}
	}
}

- (void)removeObjectIdenticalTo: (id)object
{
	id *objects;
	size_t i, count;

	if (object == nil)
		@throw [OFInvalidArgumentException
		    exceptionWithClass: [self class]];

	objects = [_array items];
	count = [_array count];

	for (i = 0; i < count; i++) {
		if (objects[i] == object) {
			[_array removeItemAtIndex: i];
			_mutations++;

			[object release];

			return;
		}
	}
}

- (void)removeObjectAtIndex: (size_t)index
{
	id object = [self objectAtIndex: index];
	[_array removeItemAtIndex: index];
	[object release];

	_mutations++;
}

- (void)removeAllObjects
{
	id *objects = [_array items];
	size_t i, count = [_array count];

	for (i = 0; i < count; i++)
		[objects[i] release];

	[_array removeAllItems];
}

- (void)removeObjectsInRange: (of_range_t)range
{
	id *objects = [_array items], *copy;
	size_t i, count = [_array count];

	if (range.length > SIZE_MAX - range.location ||
	    range.length > count - range.location)
		@throw [OFOutOfRangeException exceptionWithClass: [self class]];

	copy = [self allocMemoryWithSize: sizeof(*copy)
				   count: range.length];
	memcpy(copy, objects + range.location, range.length * sizeof(id));

	@try {
		[_array removeItemsInRange: range];
		_mutations++;

		for (i = 0; i < range.length; i++)
			[copy[i] release];
	} @finally {
		[self freeMemory: copy];
	}
}

- (void)removeLastObject
{
	size_t count = [_array count];
	id object;

	if (count == 0)
		return;

	object = [self objectAtIndex: count - 1];
	[_array removeLastItem];
	[object release];

	_mutations++;
}

- (void)exchangeObjectAtIndex: (size_t)index1
	    withObjectAtIndex: (size_t)index2
{
	id *objects = [_array items];
	size_t count = [_array count];
	id tmp;

	if (index1 >= count || index2 >= count)
		@throw [OFOutOfRangeException exceptionWithClass: [self class]];

	tmp = objects[index1];
	objects[index1] = objects[index2];
	objects[index2] = tmp;
}

- (void)reverse
{
	id *objects = [_array items];
	size_t i, j, count = [_array count];

	if (count == 0 || count == 1)
		return;

	for (i = 0, j = count - 1; i < j; i++, j--) {
		id tmp = objects[i];
		objects[i] = objects[j];
		objects[j] = tmp;
	}
}

- (int)countByEnumeratingWithState: (of_fast_enumeration_state_t*)state
			   objects: (id*)objects
			     count: (int)count
{
	/*
	 * Super means the implementation from OFArray here, as OFMutableArray
	 * does not reimplement it. As OFArray_adjacent does not reimplement it
	 * either, this is fine.
	 */
	int ret = [super countByEnumeratingWithState: state
					     objects: objects
					       count: count];

	state->mutationsPtr = &_mutations;

	return ret;
}

- (OFEnumerator*)objectEnumerator
{
	return [[[OFArrayEnumerator alloc]
	    initWithArray: self
	     mutationsPtr: &_mutations] autorelease];
}

#ifdef OF_HAVE_BLOCKS
- (void)enumerateObjectsUsingBlock: (of_array_enumeration_block_t)block
{
	id *objects = [_array items];
	size_t i, count = [_array count];
	BOOL stop = NO;
	unsigned long mutations = _mutations;

	for (i = 0; i < count && !stop; i++) {
		if (_mutations != mutations)
			@throw [OFEnumerationMutationException
			    exceptionWithClass: [self class]
					object: self];

		block(objects[i], i, &stop);
	}
}

- (void)replaceObjectsUsingBlock: (of_array_replace_block_t)block
{
	id *objects = [_array items];
	size_t i, count = [_array count];
	BOOL stop = NO;
	unsigned long mutations = _mutations;

	for (i = 0; i < count && !stop; i++) {
		id newObject;

		if (_mutations != mutations)
			@throw [OFEnumerationMutationException
			    exceptionWithClass: [self class]
					object: self];

		newObject = block(objects[i], i, &stop);

		if (newObject == nil)
			@throw [OFInvalidArgumentException
			    exceptionWithClass: [self class]
				      selector: _cmd];

		[newObject retain];
		[objects[i] release];
		objects[i] = newObject;
	}
}
#endif

- (void)makeImmutable
{
	object_setClass(self, [OFArray_adjacent class]);
}
@end
