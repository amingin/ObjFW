/*
 * Copyright (c) 2008 - 2010
 *   Jonathan Schleifer <js@webkeks.org>
 *
 * All rights reserved.
 *
 * This file is part of ObjFW. It may be distributed under the terms of the
 * Q Public License 1.0, which can be found in the file LICENSE included in
 * the packaging of this file.
 */

#include "config.h"

#import "OFXMLElement.h"
#import "OFString.h"
#import "OFArray.h"
#import "OFAutoreleasePool.h"
#import "OFString.h"
#import "OFExceptions.h"

#import "TestsAppDelegate.h"

static OFString *module = @"OFXMLElement";

@implementation TestsAppDelegate (OFXMLElementTests)
- (void)XMLElementTests
{
	OFAutoreleasePool *pool = [[OFAutoreleasePool alloc] init];
	OFXMLElement *elem[4];

	TEST(@"+[elementWithName:]",
	    (elem[0] = [OFXMLElement elementWithName: @"foo"]) &&
	    [[elem[0] string] isEqual: @"<foo/>"])

	TEST(@"+[elementWithName:stringValue:]",
	    (elem[1] = [OFXMLElement elementWithName: @"foo"
					 stringValue: @"b&ar"]) &&
	    [[elem[1] string] isEqual: @"<foo>b&amp;ar</foo>"])

	TEST(@"+[elementWithName:namespace:]",
	    (elem[2] = [OFXMLElement elementWithName: @"foo"
					   namespace: @"urn:objfw:test"]) &&
	    R([elem[2] addAttributeWithName: @"test"
				stringValue: @"test"]) &&
	    R([elem[2] setPrefix: @"objfw-test"
		    forNamespace: @"urn:objfw:test"]) &&
	    [[elem[2] string] isEqual: @"<objfw-test:foo test='test'/>"])

	TEST(@"+[elementWithName:namespace:stringValue:]",
	    (elem[3] = [OFXMLElement elementWithName: @"foo"
					   namespace: @"urn:objfw:test"
					 stringValue: @"x"]) &&
	    R([elem[3] setPrefix: @"objfw-test"
		    forNamespace: @"urn:objfw:test"]) &&
	    [[elem[3] string] isEqual: @"<objfw-test:foo>x</objfw-test:foo>"])

	TEST(@"+[elementWithCharacters:]",
	    (elem[3] = [OFXMLElement elementWithCharacters: @"<foo>"]) &&
	    [[elem[3] string] isEqual: @"&lt;foo&gt;"])

	TEST(@"+[elementWithCDATA:]",
	    (elem[3] = [OFXMLElement elementWithCDATA: @"<foo>"]) &&
	    [[elem[3] string] isEqual: @"<![CDATA[<foo>]]>"]);

	TEST(@"+[elementWithComment:]",
	    (elem[3] = [OFXMLElement elementWithComment: @" comment "]) &&
	    [[elem[3] string] isEqual: @"<!-- comment -->"])

	TEST(@"-[addAttributeWithName:stringValue:]",
	    R([elem[0] addAttributeWithName: @"foo"
				stringValue: @"b&ar"]) &&
	    [[elem[0] string] isEqual: @"<foo foo='b&amp;ar'/>"] &&
	    R([elem[1] addAttributeWithName: @"foo"
				stringValue: @"b&ar"]) &&
	    [[elem[1] string] isEqual: @"<foo foo='b&amp;ar'>b&amp;ar</foo>"])

	TEST(@"-[setPrefix:forNamespace:]",
	    R([elem[1] setPrefix: @"objfw-test"
		    forNamespace: @"urn:objfw:test"]))

	TEST(@"-[addAttributeWithName:namespace:stringValue:]",
	    R([elem[1] addAttributeWithName: @"foo"
				  namespace: @"urn:objfw:test"
				stringValue: @"bar"]) &&
	    [[elem[1] string] isEqual:
	    @"<foo foo='b&amp;ar' objfw-test:foo='bar'>b&amp;ar</foo>"])

	TEST(@"-[addChild:]",
	    R([elem[0] addChild: [OFXMLElement elementWithName: @"bar"]]) &&
	    [[elem[0] string] isEqual: @"<foo foo='b&amp;ar'><bar/></foo>"] &&
	    R([elem[2] addChild:
	    [OFXMLElement elementWithName: @"bar"
				namespace: @"urn:objfw:test"]]) &&
	    [[elem[2] string] isEqual:
	    @"<objfw-test:foo test='test'><objfw-test:bar/></objfw-test:foo>"])

	[pool drain];
}
@end
