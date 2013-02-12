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

#include <stdarg.h>
#include <stdlib.h>
#include <string.h>
#include <assert.h>

#import "OFString.h"
#import "OFString_UTF8.h"
#import "OFMutableString_UTF8.h"

#import "OFInvalidArgumentException.h"
#import "OFInvalidEncodingException.h"
#import "OFInvalidFormatException.h"
#import "OFOutOfMemoryException.h"
#import "OFOutOfRangeException.h"

#import "autorelease.h"
#import "macros.h"

#import "of_asprintf.h"
#import "unicode.h"

@implementation OFMutableString_UTF8
+ (void)initialize
{
	if (self == [OFMutableString_UTF8 class])
		[self inheritMethodsFromClass: [OFString_UTF8 class]];
}

- initWithUTF8StringNoCopy: (char*)UTF8String
	      freeWhenDone: (BOOL)freeWhenDone
{
	@try {
		self = [self initWithUTF8String: UTF8String];
	} @finally {
		if (freeWhenDone)
			free(UTF8String);
	}

	return self;
}

- (void)OF_convertWithWordStartTable: (const of_unichar_t *const[])startTable
		     wordMiddleTable: (const of_unichar_t *const[])middleTable
		  wordStartTableSize: (size_t)startTableSize
		 wordMiddleTableSize: (size_t)middleTableSize
{
	of_unichar_t *unicodeString;
	size_t unicodeLen, newCStringLength;
	size_t i, j;
	char *newCString;
	BOOL isStart = YES;

	if (!_s->isUTF8) {
		uint8_t t;
		const of_unichar_t *const *table;

		assert(startTableSize >= 1 && middleTableSize >= 1);

		_s->hashed = NO;

		for (i = 0; i < _s->cStringLength; i++) {
			if (isStart)
				table = startTable;
			else
				table = middleTable;

			switch (_s->cString[i]) {
			case ' ':
			case '\t':
			case '\n':
			case '\r':
				isStart = YES;
				break;
			default:
				isStart = NO;
				break;
			}

			if ((t = table[0][(uint8_t)_s->cString[i]]) != 0)
				_s->cString[i] = t;
		}

		return;
	}

	unicodeLen = [self length];
	unicodeString = [self allocMemoryWithSize: sizeof(of_unichar_t)
					    count: unicodeLen];

	i = j = 0;
	newCStringLength = 0;

	while (i < _s->cStringLength) {
		const of_unichar_t *const *table;
		size_t tableSize;
		of_unichar_t c;
		size_t cLen;

		if (isStart) {
			table = startTable;
			tableSize = middleTableSize;
		} else {
			table = middleTable;
			tableSize = middleTableSize;
		}

		cLen = of_string_utf8_decode(_s->cString + i,
		    _s->cStringLength - i, &c);

		if (cLen == 0 || c > 0x10FFFF) {
			[self freeMemory: unicodeString];
			@throw [OFInvalidEncodingException
			    exceptionWithClass: [self class]];
		}

		switch (c) {
		case ' ':
		case '\t':
		case '\n':
		case '\r':
			isStart = YES;
			break;
		default:
			isStart = NO;
			break;
		}

		if (c >> 8 < tableSize) {
			of_unichar_t tc = table[c >> 8][c & 0xFF];

			if (tc)
				c = tc;
		}
		unicodeString[j++] = c;

		if (c < 0x80)
			newCStringLength++;
		else if (c < 0x800)
			newCStringLength += 2;
		else if (c < 0x10000)
			newCStringLength += 3;
		else if (c < 0x110000)
			newCStringLength += 4;
		else {
			[self freeMemory: unicodeString];
			@throw [OFInvalidEncodingException
			    exceptionWithClass: [self class]];
		}

		i += cLen;
	}

	@try {
		newCString = [self allocMemoryWithSize: newCStringLength + 1];
	} @catch (id e) {
		[self freeMemory: unicodeString];
		@throw e;
	}

	j = 0;

	for (i = 0; i < unicodeLen; i++) {
		size_t d;

		if ((d = of_string_utf8_encode(unicodeString[i],
		    newCString + j)) == 0) {
			[self freeMemory: unicodeString];
			[self freeMemory: newCString];
			@throw [OFInvalidEncodingException
			    exceptionWithClass: [self class]];
		}
		j += d;
	}

	assert(j == newCStringLength);
	newCString[j] = 0;
	[self freeMemory: unicodeString];

	[self freeMemory: _s->cString];
	_s->hashed = NO;
	_s->cString = newCString;
	_s->cStringLength = newCStringLength;

	/*
	 * Even though cStringLength can change, length cannot, therefore no
	 * need to change it.
	 */
}

- (void)setCharacter: (of_unichar_t)character
	     atIndex: (size_t)index
{
	char buffer[4];
	of_unichar_t c;
	size_t lenNew, lenOld;

	if (_s->isUTF8)
		index = of_string_utf8_get_position(_s->cString, index,
		    _s->cStringLength);

	if (index > _s->cStringLength)
		@throw [OFOutOfRangeException exceptionWithClass: [self class]];

	/* Shortcut if old and new character both are ASCII */
	if (!(character & 0x80) && !(_s->cString[index] & 0x80)) {
		_s->hashed = NO;
		_s->cString[index] = character;
		return;
	}

	if ((lenNew = of_string_utf8_encode(character, buffer)) == 0)
		@throw [OFInvalidEncodingException
		    exceptionWithClass: [self class]];

	if ((lenOld = of_string_utf8_decode(_s->cString + index,
	    _s->cStringLength - index, &c)) == 0)
		@throw [OFInvalidEncodingException
		    exceptionWithClass: [self class]];

	_s->hashed = NO;

	if (lenNew == lenOld)
		memcpy(_s->cString + index, buffer, lenNew);
	else if (lenNew > lenOld) {
		_s->cString = [self resizeMemory: _s->cString
					    size: _s->cStringLength -
						  lenOld + lenNew + 1];

		memmove(_s->cString + index + lenNew,
		    _s->cString + index + lenOld,
		    _s->cStringLength - index - lenOld);
		memcpy(_s->cString + index, buffer, lenNew);

		_s->cStringLength -= lenOld;
		_s->cStringLength += lenNew;
		_s->cString[_s->cStringLength] = '\0';

		if (character & 0x80)
			_s->isUTF8 = YES;
	} else if (lenNew < lenOld) {
		memmove(_s->cString + index + lenNew,
		    _s->cString + index + lenOld,
		    _s->cStringLength - index - lenOld);
		memcpy(_s->cString + index, buffer, lenNew);

		_s->cStringLength -= lenOld;
		_s->cStringLength += lenNew;
		_s->cString[_s->cStringLength] = '\0';

		@try {
			_s->cString = [self
			    resizeMemory: _s->cString
				    size: _s->cStringLength + 1];
		} @catch (OFOutOfMemoryException *e) {
			/* We don't really care, as we only made it smaller */
		}
	} else
		assert(0);
}

- (void)appendUTF8String: (const char*)UTF8String
{
	size_t UTF8StringLength = strlen(UTF8String);
	size_t length;

	if (UTF8StringLength >= 3 && !memcmp(UTF8String, "\xEF\xBB\xBF", 3)) {
		UTF8String += 3;
		UTF8StringLength -= 3;
	}

	switch (of_string_utf8_check(UTF8String, UTF8StringLength, &length)) {
	case 1:
		_s->isUTF8 = YES;
		break;
	case -1:
		@throw [OFInvalidEncodingException
		    exceptionWithClass: [self class]];
	}

	_s->hashed = NO;
	_s->cString = [self resizeMemory: _s->cString
				    size: _s->cStringLength +
					  UTF8StringLength + 1];
	memcpy(_s->cString + _s->cStringLength, UTF8String,
	    UTF8StringLength + 1);

	_s->cStringLength += UTF8StringLength;
	_s->length += length;
}

- (void)appendUTF8String: (const char*)UTF8String
		  length: (size_t)UTF8StringLength
{
	size_t length;

	if (UTF8StringLength >= 3 && !memcmp(UTF8String, "\xEF\xBB\xBF", 3)) {
		UTF8String += 3;
		UTF8StringLength -= 3;
	}

	switch (of_string_utf8_check(UTF8String, UTF8StringLength, &length)) {
	case 1:
		_s->isUTF8 = YES;
		break;
	case -1:
		@throw [OFInvalidEncodingException
		    exceptionWithClass: [self class]];
	}

	_s->hashed = NO;
	_s->cString = [self resizeMemory: _s->cString
				    size: _s->cStringLength +
					  UTF8StringLength + 1];
	memcpy(_s->cString + _s->cStringLength, UTF8String, UTF8StringLength);

	_s->cStringLength += UTF8StringLength;
	_s->length += length;

	_s->cString[_s->cStringLength] = 0;
}

- (void)appendCString: (const char*)cString
	     encoding: (of_string_encoding_t)encoding
{
	return [self appendCString: cString
			  encoding: encoding
			    length: strlen(cString)];
}

- (void)appendCString: (const char*)cString
	     encoding: (of_string_encoding_t)encoding
	       length: (size_t)cStringLength
{
	if (encoding == OF_STRING_ENCODING_UTF_8)
		[self appendUTF8String: cString
				length: cStringLength];
	else {
		void *pool = objc_autoreleasePoolPush();
		[self appendString:
		    [OFString stringWithCString: cString
				       encoding: encoding
					 length: cStringLength]];
		objc_autoreleasePoolPop(pool);
	}
}

- (void)appendString: (OFString*)string
{
	size_t UTF8StringLength;

	if (string == nil)
		@throw [OFInvalidArgumentException
		    exceptionWithClass: [self class]
			      selector: _cmd];

	UTF8StringLength = [string UTF8StringLength];

	_s->hashed = NO;
	_s->cString = [self resizeMemory: _s->cString
				    size: _s->cStringLength +
					  UTF8StringLength + 1];
	memcpy(_s->cString + _s->cStringLength, [string UTF8String],
	    UTF8StringLength);

	_s->cStringLength += UTF8StringLength;
	_s->length += [string length];

	_s->cString[_s->cStringLength] = 0;

	if ([string isKindOfClass: [OFString_UTF8 class]] ||
	    [string isKindOfClass: [OFMutableString_UTF8 class]]) {
		if (((OFString_UTF8*)string)->_s->isUTF8)
			_s->isUTF8 = YES;
	} else
		_s->isUTF8 = YES;
}

- (void)appendCharacters: (of_unichar_t*)characters
		  length: (size_t)length
{
	char *tmp;

	tmp = [self allocMemoryWithSize: (length * 4) + 1];
	@try {
		size_t i, j = 0;
		BOOL isUTF8 = NO;

		for (i = 0; i < length; i++) {
			char buffer[4];

			switch (of_string_utf8_encode(characters[i], buffer)) {
			case 1:
				tmp[j++] = buffer[0];
				break;
			case 2:
				isUTF8 = YES;

				memcpy(tmp + j, buffer, 2);
				j += 2;

				break;
			case 3:
				isUTF8 = YES;

				memcpy(tmp + j, buffer, 3);
				j += 3;

				break;
			case 4:
				isUTF8 = YES;

				memcpy(tmp + j, buffer, 4);
				j += 4;

				break;
			default:
				@throw [OFInvalidEncodingException
				    exceptionWithClass: [self class]];
			}
		}

		tmp[j] = '\0';

		_s->hashed = NO;
		_s->cString = [self resizeMemory: _s->cString
					    size: _s->cStringLength + j + 1];
		memcpy(_s->cString + _s->cStringLength, tmp, j + 1);

		_s->cStringLength += j;
		_s->length += length;

		if (isUTF8)
			_s->isUTF8 = YES;
	} @finally {
		[self freeMemory: tmp];
	}
}

- (void)appendFormat: (OFConstantString*)format
	   arguments: (va_list)arguments
{
	char *UTF8String;
	int UTF8StringLength;

	if (format == nil)
		@throw [OFInvalidArgumentException
		    exceptionWithClass: [self class]
			      selector: _cmd];

	if ((UTF8StringLength = of_vasprintf(&UTF8String, [format UTF8String],
	    arguments)) == -1)
		@throw [OFInvalidFormatException
		    exceptionWithClass: [self class]];

	@try {
		[self appendUTF8String: UTF8String
				length: UTF8StringLength];
	} @finally {
		free(UTF8String);
	}
}

- (void)reverse
{
	size_t i, j;

	_s->hashed = NO;

	/* We reverse all bytes and restore UTF-8 later, if necessary */
	for (i = 0, j = _s->cStringLength - 1; i < _s->cStringLength / 2;
	    i++, j--) {
		_s->cString[i] ^= _s->cString[j];
		_s->cString[j] ^= _s->cString[i];
		_s->cString[i] ^= _s->cString[j];
	}

	if (!_s->isUTF8)
		return;

	for (i = 0; i < _s->cStringLength; i++) {
		/* ASCII */
		if OF_LIKELY (!(_s->cString[i] & 0x80))
			continue;

		/* A start byte can't happen first as we reversed everything */
		if OF_UNLIKELY (_s->cString[i] & 0x40)
			@throw [OFInvalidEncodingException
			    exceptionWithClass: [self class]];

		/* Next byte must not be ASCII */
		if OF_UNLIKELY (_s->cStringLength < i + 1 ||
		    !(_s->cString[i + 1] & 0x80))
			@throw [OFInvalidEncodingException
			    exceptionWithClass: [self class]];

		/* Next byte is the start byte */
		if OF_LIKELY (_s->cString[i + 1] & 0x40) {
			_s->cString[i] ^= _s->cString[i + 1];
			_s->cString[i + 1] ^= _s->cString[i];
			_s->cString[i] ^= _s->cString[i + 1];

			i++;
			continue;
		}

		/* Second next byte must not be ASCII */
		if OF_UNLIKELY (_s->cStringLength < i + 2 ||
		    !(_s->cString[i + 2] & 0x80))
			@throw [OFInvalidEncodingException
			    exceptionWithClass: [self class]];

		/* Second next byte is the start byte */
		if OF_LIKELY (_s->cString[i + 2] & 0x40) {
			_s->cString[i] ^= _s->cString[i + 2];
			_s->cString[i + 2] ^= _s->cString[i];
			_s->cString[i] ^= _s->cString[i + 2];

			i += 2;
			continue;
		}

		/* Third next byte must not be ASCII */
		if OF_UNLIKELY (_s->cStringLength < i + 3 ||
		    !(_s->cString[i + 3] & 0x80))
			@throw [OFInvalidEncodingException
			    exceptionWithClass: [self class]];

		/* Third next byte is the start byte */
		if OF_LIKELY (_s->cString[i + 3] & 0x40) {
			_s->cString[i] ^= _s->cString[i + 3];
			_s->cString[i + 3] ^= _s->cString[i];
			_s->cString[i] ^= _s->cString[i + 3];

			_s->cString[i + 1] ^= _s->cString[i + 2];
			_s->cString[i + 2] ^= _s->cString[i + 1];
			_s->cString[i + 1] ^= _s->cString[i + 2];

			i += 3;
			continue;
		}

		/* UTF-8 does not allow more than 4 bytes per character */
		@throw [OFInvalidEncodingException
		    exceptionWithClass: [self class]];
	}
}

- (void)insertString: (OFString*)string
	     atIndex: (size_t)index
{
	size_t newCStringLength;

	if (index > _s->length)
		@throw [OFOutOfRangeException
		    exceptionWithClass: [self class]];

	if (_s->isUTF8)
		index = of_string_utf8_get_position(_s->cString, index,
		    _s->cStringLength);

	newCStringLength = _s->cStringLength + [string UTF8StringLength];
	_s->hashed = NO;
	_s->cString = [self resizeMemory: _s->cString
				    size: newCStringLength + 1];

	memmove(_s->cString + index + [string UTF8StringLength],
	    _s->cString + index, _s->cStringLength - index);
	memcpy(_s->cString + index, [string UTF8String],
	    [string UTF8StringLength]);
	_s->cString[newCStringLength] = '\0';

	_s->cStringLength = newCStringLength;
	_s->length += [string length];

	if ([string isKindOfClass: [OFString_UTF8 class]] ||
	    [string isKindOfClass: [OFMutableString_UTF8 class]]) {
		if (((OFString_UTF8*)string)->_s->isUTF8)
			_s->isUTF8 = YES;
	} else
		_s->isUTF8 = YES;
}

- (void)deleteCharactersInRange: (of_range_t)range
{
	size_t start = range.location;
	size_t end = range.location + range.length;

	if (range.length > SIZE_MAX - range.location || end > _s->length)
		@throw [OFOutOfRangeException exceptionWithClass: [self class]];

	if (_s->isUTF8) {
		start = of_string_utf8_get_position(_s->cString, start,
		    _s->cStringLength);
		end = of_string_utf8_get_position(_s->cString, end,
		    _s->cStringLength);
	}

	memmove(_s->cString + start, _s->cString + end,
	    _s->cStringLength - end);
	_s->hashed = NO;
	_s->length -= range.length;
	_s->cStringLength -= end - start;
	_s->cString[_s->cStringLength] = 0;

	@try {
		_s->cString = [self resizeMemory: _s->cString
					    size: _s->cStringLength + 1];
	} @catch (OFOutOfMemoryException *e) {
		/* We don't really care, as we only made it smaller */
	}
}

- (void)replaceCharactersInRange: (of_range_t)range
		      withString: (OFString*)replacement
{
	size_t start = range.location;
	size_t end = range.location + range.length;
	size_t newCStringLength, newLength;

	if (range.length > SIZE_MAX - range.location || end > _s->length)
		@throw [OFOutOfRangeException exceptionWithClass: [self class]];

	newLength = _s->length - range.length + [replacement length];

	if (_s->isUTF8) {
		start = of_string_utf8_get_position(_s->cString, start,
		    _s->cStringLength);
		end = of_string_utf8_get_position(_s->cString, end,
		    _s->cStringLength);
	}

	newCStringLength = _s->cStringLength - (end - start) +
	    [replacement UTF8StringLength];
	_s->hashed = NO;
	_s->cString = [self resizeMemory: _s->cString
				    size: newCStringLength + 1];

	memmove(_s->cString + start + [replacement UTF8StringLength],
	    _s->cString + end, _s->cStringLength - end);
	memcpy(_s->cString + start, [replacement UTF8String],
	    [replacement UTF8StringLength]);
	_s->cString[newCStringLength] = '\0';

	_s->cStringLength = newCStringLength;
	_s->length = newLength;
}

- (void)replaceOccurrencesOfString: (OFString*)string
			withString: (OFString*)replacement
			   options: (int)options
			     range: (of_range_t)range
{
	const char *searchString = [string UTF8String];
	const char *replacementString = [replacement UTF8String];
	size_t searchLength = [string UTF8StringLength];
	size_t replacementLength = [replacement UTF8StringLength];
	size_t i, last, newCStringLength, newLength;
	char *newCString;

	if (range.length > SIZE_MAX - range.location ||
	    range.location + range.length > [self length])
		@throw [OFOutOfRangeException exceptionWithClass: [self class]];

	if (_s->isUTF8) {
		range.location = of_string_utf8_get_position(_s->cString,
		    range.location, _s->cStringLength);
		range.length = of_string_utf8_get_position(
		    _s->cString + range.location, range.length,
		    _s->cStringLength - range.location);
	}

	if ([string UTF8StringLength] > range.length)
		return;

	newCString = NULL;
	newCStringLength = 0;
	newLength = _s->length;

	last = 0;
	for (i = range.location; i <= range.length - searchLength; i++) {
		if (memcmp(_s->cString + i, searchString, searchLength))
			continue;

		@try {
			newCString = [self
			    resizeMemory: newCString
				    size: newCStringLength + i - last +
					  replacementLength + 1];
		} @catch (id e) {
			[self freeMemory: newCString];
			@throw e;
		}
		memcpy(newCString + newCStringLength, _s->cString + last,
		    i - last);
		memcpy(newCString + newCStringLength + i - last,
		    replacementString, replacementLength);

		newCStringLength += i - last + replacementLength;
		newLength = newLength - [string length] + [replacement length];

		i += searchLength - 1;
		last = i + 1;
	}

	@try {
		newCString = [self resizeMemory: newCString
					   size: newCStringLength +
						 _s->cStringLength - last + 1];
	} @catch (id e) {
		[self freeMemory: newCString];
		@throw e;
	}
	memcpy(newCString + newCStringLength, _s->cString + last,
	    _s->cStringLength - last);
	newCStringLength += _s->cStringLength - last;
	newCString[newCStringLength] = 0;

	[self freeMemory: _s->cString];
	_s->hashed = NO;
	_s->cString = newCString;
	_s->cStringLength = newCStringLength;
	_s->length = newLength;
}

- (void)deleteLeadingWhitespaces
{
	size_t i;

	for (i = 0; i < _s->cStringLength; i++)
		if (_s->cString[i] != ' '  && _s->cString[i] != '\t' &&
		    _s->cString[i] != '\n' && _s->cString[i] != '\r' &&
		    _s->cString[i] != '\f')
			break;

	_s->hashed = NO;
	_s->cStringLength -= i;
	_s->length -= i;

	memmove(_s->cString, _s->cString + i, _s->cStringLength);
	_s->cString[_s->cStringLength] = '\0';

	@try {
		_s->cString = [self resizeMemory: _s->cString
					    size: _s->cStringLength + 1];
	} @catch (OFOutOfMemoryException *e) {
		/* We don't really care, as we only made it smaller */
	}
}

- (void)deleteTrailingWhitespaces
{
	size_t d;
	char *p;

	_s->hashed = NO;

	d = 0;
	for (p = _s->cString + _s->cStringLength - 1; p >= _s->cString; p--) {
		if (*p != ' ' && *p != '\t' && *p != '\n' && *p != '\r' &&
		    *p != '\f')
			break;

		*p = '\0';
		d++;
	}

	_s->cStringLength -= d;
	_s->length -= d;

	@try {
		_s->cString = [self resizeMemory: _s->cString
					    size: _s->cStringLength + 1];
	} @catch (OFOutOfMemoryException *e) {
		/* We don't really care, as we only made it smaller */
	}
}

- (void)deleteEnclosingWhitespaces
{
	size_t d, i;
	char *p;

	_s->hashed = NO;

	d = 0;
	for (p = _s->cString + _s->cStringLength - 1; p >= _s->cString; p--) {
		if (*p != ' ' && *p != '\t' && *p != '\n' && *p != '\r' &&
		    *p != '\f')
			break;

		*p = '\0';
		d++;
	}

	_s->cStringLength -= d;
	_s->length -= d;

	for (i = 0; i < _s->cStringLength; i++)
		if (_s->cString[i] != ' '  && _s->cString[i] != '\t' &&
		    _s->cString[i] != '\n' && _s->cString[i] != '\r' &&
		    _s->cString[i] != '\f')
			break;

	_s->cStringLength -= i;
	_s->length -= i;

	memmove(_s->cString, _s->cString + i, _s->cStringLength);
	_s->cString[_s->cStringLength] = '\0';

	@try {
		_s->cString = [self resizeMemory: _s->cString
					    size: _s->cStringLength + 1];
	} @catch (OFOutOfMemoryException *e) {
		/* We don't really care, as we only made it smaller */
	}
}

- (void)makeImmutable
{
	object_setClass(self, [OFString_UTF8 class]);
}
@end
