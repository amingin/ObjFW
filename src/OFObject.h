/*
 * Copyright (c) 2008
 *   Jonathan Schleifer <js@webkeks.org>
 *
 * All rights reserved.
 *
 * This file is part of libobjfw. It may be distributed under the terms of the
 * Q Public License 1.0, which can be found in the file LICENSE included in
 * the packaging of this file.
 */

#import <objc/Object.h>
#import <stdint.h>

/**
 * The OFObject class is the base class for all other classes inside ObjFW.
 */
@interface OFObject: Object
{
	void **__memchunks;
	size_t __memchunks_size;
}

/**
 * Initialize the already allocated object.
 * Also sets up the memory pool for the object.
 *
 * \return An initialized object
 */
- init;

/**
 * Allocate memory and store it in the objects memory pool so it can be free'd
 * automatically when the object is free'd.
 *
 * \param size The size of the memory to allocate
 * \return A pointer to the allocated memory
 */
- (void*)getMemWithSize: (size_t)size;

/**
 * Allocate memory for a specified number of items and store it in the objects
 * memory pool so it can be free'd automatically when the object is free'd.
 *
 * \param nitems The number of items to allocate
 * \param size The size of each item to allocate
 * \return A pointer to the allocated memory
 */
- (void*)getMemForNItems: (size_t)nitems
		  ofSize: (size_t)size;

/**
 * Resize memory in the memory pool to a specified size.
 *
 * \param ptr A pointer to the already allocated memory
 * \param size The new size for the memory chunk
 * \return A pointer to the resized memory chunk
 */
- (void*)resizeMem: (void*)ptr
	    toSize: (size_t)size;

/**
 * Resize memory in the memory pool to a specific number of items of a
 * specified size.
 *
 * \param ptr A pointer to the already allocated memory
 * \param nitems The number of items to resize to
 * \param size The size of each item to resize to
 * \return A pointer to the resized memory chunk
 */
- (void*)resizeMem: (void*)ptr
	  toNItems: (size_t)nitems
	    ofSize: (size_t)size;

/**
 * Frees allocated memory and removes it from the memory pool.
 *
 * \param ptr A pointer to the allocated memory
 */
- freeMem: (void*)ptr;

/**
 * Frees the object and also frees all memory allocated via its memory pool.
 */
- free;
@end
