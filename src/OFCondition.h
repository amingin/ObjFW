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

#import "OFMutex.h"

/*!
 * @brief A class implementing a condition variable for thread synchronization.
 */
@interface OFCondition: OFMutex
{
	of_condition_t _condition;
	BOOL _conditionInitialized;
}

/*!
 * @brief Creates a new condition.
 *
 * @return A new, autoreleased OFCondition
 */
+ (instancetype)condition;

/*!
 * @brief Blocks the current thread until another thread calls @ref signal or
 *	  @ref broadcast.
 */
- (void)wait;

/*!
 * @brief Signals the next waiting thread to continue.
 */
- (void)signal;

/*!
 * @brief Signals all threads to continue.
 */
- (void)broadcast;
@end
