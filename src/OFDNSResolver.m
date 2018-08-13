/*
 * Copyright (c) 2008, 2009, 2010, 2011, 2012, 2013, 2014, 2015, 2016, 2017,
 *               2018
 *   Jonathan Schleifer <js@heap.zone>
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
#include "unistd_wrapper.h"

#import "OFDNSResolver.h"
#import "OFArray.h"
#import "OFCharacterSet.h"
#import "OFData.h"
#import "OFDate.h"
#import "OFDictionary.h"
#import "OFFile.h"
#import "OFLocale.h"
#import "OFNumber.h"
#import "OFString.h"
#import "OFTimer.h"
#import "OFUDPSocket.h"
#ifdef OF_WINDOWS
# import "OFWindowsRegistryKey.h"
#endif

#import "OFInvalidArgumentException.h"
#import "OFInvalidServerReplyException.h"
#import "OFOpenItemFailedException.h"
#import "OFOutOfRangeException.h"
#import "OFResolveHostFailedException.h"
#import "OFTruncatedDataException.h"

#ifdef OF_WINDOWS
# define interface struct
# include <iphlpapi.h>
# undef interface
#endif

/*
 * RFC 1035 doesn't specify if pointers to pointers are allowed, and if so how
 * many. Since it's unspecified, we have to assume that it might happen, but we
 * also want to limit it to avoid DoS. Limiting it to 16 levels of pointers and
 * immediately rejecting pointers to itself seems like a fair balance.
 */
#define MAX_ALLOWED_POINTERS 16

#define TIMEOUT 2
#define ATTEMPTS 3

#if defined(OF_HAIKU)
# define HOSTS_PATH @"/system/settings/network/hosts"
# define RESOLV_CONF_PATH @"/system/settings/network/resolv.conf"
#elif defined(OF_MORPHOS)
# define HOSTS_PATH @"ENV:sys/net/hosts"
# define RESOLV_CONF_PATH @"ENV:sys/net/resolv.conf"
#elif defined(OF_AMIGAOS4)
# define HOSTS_PATH @"DEVS:Internet/hosts"
# define RESOLV_CONF_PATH @"DEVS:Internet/resolv.conf"
#elif defined(OF_AMIGAOS)
# define HOSTS_PATH @"AmiTCP:db/hosts"
# define RESOLV_CONF_PATH @"AmiTCP:db/resolv.conf"
#else
# define HOSTS_PATH @"/etc/hosts"
# define RESOLV_CONF_PATH @"/etc/resolv.conf"
#endif

/*
 * TODO:
 *
 *  - Resolve with each search domain
 *  - Fallback to TCP
 */

@interface OFDNSResolverQuery: OFObject
{
@public
	OFString *_host, *_domainName;
	of_dns_resource_record_class_t _recordClass;
	of_dns_resource_record_type_t _recordType;
	OFNumber *_ID;
	OFArray OF_GENERIC(OFString *) *_nameServers, *_searchDomains;
	size_t _nameServersIndex, _searchDomainsIndex;
	size_t _attempt;
	id _target;
	SEL _selector;
	id _context;
	OFData *_queryData;
	OFTimer *_cancelTimer;
}

- (instancetype)initWithHost: (OFString *)host
		  domainName: (OFString *)domainName
		 recordClass: (of_dns_resource_record_class_t)recordClass
		  recordType: (of_dns_resource_record_type_t)recordType
			  ID: (OFNumber *)ID
		 nameServers: (OFArray OF_GENERIC(OFString *) *)nameServers
	       searchDomains: (OFArray OF_GENERIC(OFString *) *)searchDomains
		      target: (id)target
		    selector: (SEL)selector
		     context: (id)context;
@end

@interface OFDNSResolver ()
- (void)of_parseConfig;
#ifdef OF_HAVE_FILES
- (void)of_parseHosts: (OFString *)path;
# ifndef OF_WINDOWS
- (void)of_parseResolvConf: (OFString *)path;
- (void)of_parseResolvConfOption: (OFString *)option;
# endif
#endif
#ifdef OF_WINDOWS
- (void)of_parseNetworkParams;
#endif
- (void)of_reloadConfig;
- (void)of_sendQuery: (OFDNSResolverQuery *)query;
- (void)of_queryWithIDTimedOut: (OFDNSResolverQuery *)query;
- (size_t)of_socket: (OFUDPSocket *)sock
      didSendBuffer: (void **)buffer
	  bytesSent: (size_t)bytesSent
	   receiver: (of_socket_address_t *)receiver
	    context: (OFDNSResolverQuery *)query
	  exception: (id)exception;
-      (bool)of_socket: (OFUDPSocket *)sock
  didReceiveIntoBuffer: (unsigned char *)buffer
		length: (size_t)length
		sender: (of_socket_address_t)sender
	       context: (id)context
	     exception: (id)exception;
@end

static OFString *
domainFromHostname(void)
{
	char hostname[256];
	char *domain;

	if (gethostname(hostname, 256) != 0)
		return nil;

	if ((domain = strchr(hostname, '.')) == NULL)
		return nil;

	return [OFString stringWithCString: domain + 1
				  encoding: [OFLocale encoding]];
}

static OFString *
parseString(const unsigned char *buffer, size_t length, size_t *i)
{
	uint8_t stringLength;
	OFString *string;

	if (*i >= length)
		@throw [OFTruncatedDataException exception];

	stringLength = buffer[(*i)++];

	if (*i + stringLength > length)
		@throw [OFTruncatedDataException exception];

	string = [OFString stringWithUTF8String: (char *)&buffer[*i]
					 length: stringLength];
	*i += stringLength;

	return string;
}

static OFString *
parseName(const unsigned char *buffer, size_t length, size_t *i,
    uint_fast8_t pointerLevel)
{
	OFMutableArray *components = [OFMutableArray array];
	uint8_t componentLength;

	do {
		OFString *component;

		if (*i >= length)
			@throw [OFTruncatedDataException exception];

		componentLength = buffer[(*i)++];

		if (componentLength & 0xC0) {
			size_t j;
			OFString *suffix;

			if (pointerLevel == 0)
				@throw [OFInvalidServerReplyException
				    exception];

			if (*i >= length)
				@throw [OFTruncatedDataException exception];

			j = ((componentLength & 0x3F) << 8) | buffer[(*i)++];

			if (j == *i - 2)
				/* Pointing to itself?! */
				@throw [OFInvalidServerReplyException
				    exception];

			suffix = parseName(buffer, length, &j,
			    pointerLevel - 1);

			if ([components count] == 0)
				return suffix;
			else {
				[components addObject: suffix];
				return [components
				    componentsJoinedByString: @"."];
			}
		}

		if (*i + componentLength > length)
			@throw [OFTruncatedDataException exception];

		component = [OFString stringWithUTF8String: (char *)&buffer[*i]
						    length: componentLength];
		*i += componentLength;

		[components addObject: component];
	} while (componentLength > 0);

	return [components componentsJoinedByString: @"."];
}

static OF_KINDOF(OFDNSResourceRecord *)
parseResourceRecord(OFString *name, of_dns_resource_record_class_t recordClass,
    of_dns_resource_record_type_t recordType, uint32_t TTL,
    const unsigned char *buffer, size_t length, size_t i, uint16_t dataLength)
{
	if (recordType == OF_DNS_RESOURCE_RECORD_TYPE_A &&
	    recordClass == OF_DNS_RESOURCE_RECORD_CLASS_IN) {
		of_socket_address_t address;

		if (dataLength != 4)
			@throw [OFInvalidServerReplyException exception];

		memset(&address, 0, sizeof(address));
		address.family = OF_SOCKET_ADDRESS_FAMILY_IPV4;
		address.length = sizeof(address.sockaddr.in);

		address.sockaddr.in.sin_family = AF_INET;
		memcpy(&address.sockaddr.in.sin_addr.s_addr, buffer + i, 4);

		return [[[OFADNSResourceRecord alloc]
		    initWithName: name
			 address: &address
			     TTL: TTL] autorelease];
	} else if (recordType == OF_DNS_RESOURCE_RECORD_TYPE_NS) {
		size_t j = i;
		OFString *authoritativeHost = parseName(buffer, length, &j,
		    MAX_ALLOWED_POINTERS);

		if (j != i + dataLength)
			@throw [OFInvalidServerReplyException exception];

		return [[[OFNSDNSResourceRecord alloc]
			 initWithName: name
			  recordClass: recordClass
		    authoritativeHost: authoritativeHost
				  TTL: TTL] autorelease];
	} else if (recordType == OF_DNS_RESOURCE_RECORD_TYPE_CNAME) {
		size_t j = i;
		OFString *alias = parseName(buffer, length, &j,
		    MAX_ALLOWED_POINTERS);

		if (j != i + dataLength)
			@throw [OFInvalidServerReplyException exception];

		return [[[OFCNAMEDNSResourceRecord alloc]
		    initWithName: name
		     recordClass: recordClass
			   alias: alias
			     TTL: TTL] autorelease];
	} else if (recordType == OF_DNS_RESOURCE_RECORD_TYPE_SOA) {
		size_t j = i;
		OFString *primaryNameServer = parseName(buffer, length, &j,
		    MAX_ALLOWED_POINTERS);
		OFString *responsiblePerson;
		uint32_t serialNumber, refreshInterval, retryInterval;
		uint32_t expirationInterval, minTTL;

		if (j > i + dataLength)
			@throw [OFInvalidServerReplyException exception];

		responsiblePerson = parseName(buffer, length, &j,
		    MAX_ALLOWED_POINTERS);

		if (dataLength - (j - i) != 20)
			@throw [OFInvalidServerReplyException exception];

		serialNumber = (buffer[j] << 24) | (buffer[j + 1] << 16) |
		    (buffer[j + 2] << 8) | buffer[j + 3];
		refreshInterval = (buffer[j + 4] << 24) |
		    (buffer[j + 5] << 16) | (buffer[j + 6] << 8) |
		    buffer[j + 7];
		retryInterval = (buffer[j + 8] << 24) | (buffer[j + 9] << 16) |
		    (buffer[j + 10] << 8) | buffer[j + 11];
		expirationInterval = (buffer[j + 12] << 24) |
		    (buffer[j + 13] << 16) | (buffer[j + 14] << 8) |
		    buffer[j + 15];
		minTTL = (buffer[j + 16] << 24) | (buffer[j + 17] << 16) |
		    (buffer[j + 18] << 8) | buffer[j + 19];

		return [[[OFSOADNSResourceRecord alloc]
			  initWithName: name
			   recordClass: recordClass
		     primaryNameServer: primaryNameServer
		     responsiblePerson: responsiblePerson
			  serialNumber: serialNumber
		       refreshInterval: refreshInterval
			 retryInterval: retryInterval
		    expirationInterval: expirationInterval
				minTTL: minTTL
				   TTL: TTL] autorelease];
	} else if (recordType == OF_DNS_RESOURCE_RECORD_TYPE_PTR) {
		size_t j = i;
		OFString *domainName = parseName(buffer, length, &j,
		    MAX_ALLOWED_POINTERS);

		if (j != i + dataLength)
			@throw [OFInvalidServerReplyException exception];

		return [[[OFPTRDNSResourceRecord alloc]
		    initWithName: name
		     recordClass: recordClass
		      domainName: domainName
			     TTL: TTL] autorelease];
	} else if (recordType == OF_DNS_RESOURCE_RECORD_TYPE_HINFO) {
		size_t j = i;
		OFString *CPU = parseString(buffer, length, &j);
		OFString *OS;

		if (j > i + dataLength)
			@throw [OFInvalidServerReplyException exception];

		OS = parseString(buffer, length, &j);

		if (j != i + dataLength)
			@throw [OFInvalidServerReplyException exception];

		return [[[OFHINFODNSResourceRecord alloc]
		    initWithName: name
		     recordClass: recordClass
			     CPU: CPU
			      OS: OS
			     TTL: TTL] autorelease];
	} else if (recordType == OF_DNS_RESOURCE_RECORD_TYPE_MX) {
		uint16_t preference;
		size_t j;
		OFString *mailExchange;

		if (dataLength < 2)
			@throw [OFInvalidServerReplyException exception];

		preference = (buffer[i] << 8) | buffer[i + 1];

		j = i + 2;
		mailExchange = parseName(buffer, length, &j,
		    MAX_ALLOWED_POINTERS);

		if (j != i + dataLength)
			@throw [OFInvalidServerReplyException exception];

		return [[[OFMXDNSResourceRecord alloc]
			    initWithName: name
			     recordClass: recordClass
			      preference: preference
			    mailExchange: mailExchange
				     TTL: TTL] autorelease];
	} else if (recordType == OF_DNS_RESOURCE_RECORD_TYPE_TXT) {
		OFData *textData = [OFData dataWithItems: &buffer[i]
						   count: dataLength];

		return [[[OFTXTDNSResourceRecord alloc]
		    initWithName: name
		     recordClass: recordClass
			textData: textData
			     TTL: TTL] autorelease];
	} else if (recordType == OF_DNS_RESOURCE_RECORD_TYPE_RP) {
		size_t j = i;
		OFString *mailbox = parseName(buffer, length, &j,
		    MAX_ALLOWED_POINTERS);
		OFString *TXTDomainName;

		if (j > i + dataLength)
			@throw [OFInvalidServerReplyException exception];

		TXTDomainName = parseName(buffer, length, &j,
		    MAX_ALLOWED_POINTERS);

		if (j != i + dataLength)
			@throw [OFInvalidServerReplyException exception];

		return [[[OFRPDNSResourceRecord alloc]
		    initWithName: name
		     recordClass: recordClass
			 mailbox: mailbox
		   TXTDomainName: TXTDomainName
			     TTL: TTL] autorelease];
	} else if (recordType == OF_DNS_RESOURCE_RECORD_TYPE_AAAA &&
	    recordClass == OF_DNS_RESOURCE_RECORD_CLASS_IN) {
		of_socket_address_t address;

		if (dataLength != 16)
			@throw [OFInvalidServerReplyException exception];

		memset(&address, 0, sizeof(address));
		address.family = OF_SOCKET_ADDRESS_FAMILY_IPV6;
		address.length = sizeof(address.sockaddr.in6);

#ifdef AF_INET6
		address.sockaddr.in6.sin6_family = AF_INET6;
#else
		address.sockaddr.in6.sin6_family = AF_UNSPEC;
#endif
		memcpy(address.sockaddr.in6.sin6_addr.s6_addr, buffer + i, 16);

		return [[[OFAAAADNSResourceRecord alloc]
		    initWithName: name
			 address: &address
			     TTL: TTL] autorelease];
	} else if (recordType == OF_DNS_RESOURCE_RECORD_TYPE_SRV &&
	    recordClass == OF_DNS_RESOURCE_RECORD_CLASS_IN) {
		uint16_t priority, weight, port;
		size_t j;
		OFString *target;

		if (dataLength < 6)
			@throw [OFInvalidServerReplyException exception];

		priority = (buffer[i] << 8) | buffer[i + 1];
		weight = (buffer[i + 2] << 8) | buffer[i + 3];
		port = (buffer[i + 4] << 8) | buffer[i + 5];

		j = i + 6;
		target = parseName(buffer, length, &j, MAX_ALLOWED_POINTERS);

		if (j != i + dataLength)
			@throw [OFInvalidServerReplyException exception];

		return [[[OFSRVDNSResourceRecord alloc]
			    initWithName: name
				priority: priority
				  weight: weight
				  target: target
				    port: port
				     TTL: TTL] autorelease];
	} else
		return [[[OFDNSResourceRecord alloc]
		    initWithName: name
		     recordClass: recordClass
		      recordType: recordType
			     TTL: TTL] autorelease];
}

static OFArray *
parseSection(const unsigned char *buffer, size_t length, size_t *i,
    uint_fast16_t count)
{
	OFMutableArray *ret = [OFMutableArray array];

	for (uint_fast16_t j = 0; j < count; j++) {
		OFString *name = parseName(buffer, length, i,
		    MAX_ALLOWED_POINTERS);
		of_dns_resource_record_class_t recordClass;
		of_dns_resource_record_type_t recordType;
		uint32_t TTL;
		uint16_t dataLength;
		OFDNSResourceRecord *record;

		if (*i + 10 > length)
			@throw [OFTruncatedDataException exception];

		recordType = (buffer[*i] << 16) | buffer[*i + 1];
		recordClass = (buffer[*i + 2] << 16) | buffer[*i + 3];
		TTL = (buffer[*i + 4] << 24) | (buffer[*i + 5] << 16) |
		    (buffer[*i + 6] << 8) | buffer[*i + 7];
		dataLength = (buffer[*i + 8] << 16) | buffer[*i + 9];

		*i += 10;

		if (*i + dataLength > length)
			@throw [OFTruncatedDataException exception];

		record = parseResourceRecord(name, recordClass, recordType, TTL,
		    buffer, length, *i, dataLength);
		*i += dataLength;

		[ret addObject: record];
	}

	[ret makeImmutable];

	return ret;
}

static void callback(id target, SEL selector, OFDNSResolver *resolver,
    OFString *domainName, OFArray *answerRecords, OFArray *authorityRecords,
    OFArray *additionalRecords, id context, id exception)
{
	void (*method)(id, SEL, OFDNSResolver *, OFString *, OFArray *,
	    OFArray *, OFArray *, id, id) = (void (*)(id, SEL, OFDNSResolver *,
	    OFString *, OFArray *, OFArray *, OFArray *, id, id))
	    [target methodForSelector: selector];

	method(target, selector, resolver, domainName, answerRecords,
	    authorityRecords, additionalRecords, context, exception);
}

@implementation OFDNSResolverQuery
- (instancetype)initWithHost: (OFString *)host
		  domainName: (OFString *)domainName
		 recordClass: (of_dns_resource_record_class_t)recordClass
		  recordType: (of_dns_resource_record_type_t)recordType
			  ID: (OFNumber *)ID
		 nameServers: (OFArray OF_GENERIC(OFString *) *)nameServers
	       searchDomains: (OFArray OF_GENERIC(OFString *) *)searchDomains
		      target: (id)target
		    selector: (SEL)selector
		     context: (id)context
{
	self = [super init];

	@try {
		void *pool = objc_autoreleasePoolPush();
		OFMutableData *queryData;
		uint16_t tmp;

		_host = [host copy];
		_domainName = [domainName copy];
		_recordClass = recordClass;
		_recordType = recordType;
		_ID = [ID retain];
		_nameServers = [nameServers copy];
		_searchDomains = [searchDomains copy];
		_target = [target retain];
		_selector = selector;
		_context = [context retain];

		queryData = [OFMutableData dataWithCapacity: 512];

		/* Header */

		tmp = OF_BSWAP16_IF_LE([ID uInt16Value]);
		[queryData addItems: &tmp
			      count: 2];

		/* RD */
		tmp = OF_BSWAP16_IF_LE(1 << 8);
		[queryData addItems: &tmp
			      count: 2];

		/* QDCOUNT */
		tmp = OF_BSWAP16_IF_LE(1);
		[queryData addItems: &tmp
			      count: 2];

		/* ANCOUNT, NSCOUNT and ARCOUNT */
		[queryData increaseCountBy: 6];

		/* Question */

		/* QNAME */
		for (OFString *component in
		    [domainName componentsSeparatedByString: @"."]) {
			size_t length = [component UTF8StringLength];
			uint8_t length8;

			if (length > 63 || [queryData count] + length > 512)
				@throw [OFOutOfRangeException exception];

			length8 = (uint8_t)length;
			[queryData addItem: &length8];
			[queryData addItems: [component UTF8String]
				      count: length];
		}

		/* QTYPE */
		tmp = OF_BSWAP16_IF_LE(recordType);
		[queryData addItems: &tmp
			      count: 2];

		/* QCLASS */
		tmp = OF_BSWAP16_IF_LE(recordClass);
		[queryData addItems: &tmp
			 count: 2];

		[queryData makeImmutable];

		_queryData = [queryData copy];

		objc_autoreleasePoolPop(pool);
	} @catch (id e) {
		[self release];
		@throw e;
	}

	return self;
}

- (void)dealloc
{
	[_host release];
	[_domainName release];
	[_ID release];
	[_nameServers release];
	[_searchDomains release];
	[_target release];
	[_context release];
	[_queryData release];
	[_cancelTimer release];

	[super dealloc];
}
@end

@implementation OFDNSResolver
@synthesize staticHosts = _staticHosts, nameServers = _nameServers;
@synthesize localDomain = _localDomain, searchDomains = _searchDomains;
@synthesize minNumberOfDotsInAbsoluteName = _minNumberOfDotsInAbsoluteName;
@synthesize usesTCP = _usesTCP, configReloadInterval = _configReloadInterval;

+ (instancetype)resolver
{
	return [[[self alloc] init] autorelease];
}

- (instancetype)init
{
	self = [super init];

	@try {
		_queries = [[OFMutableDictionary alloc] init];

		[self of_parseConfig];
	} @catch (id e) {
		[self release];
		@throw e;
	}

	return self;
}

- (void)of_parseConfig
{
	void *pool = objc_autoreleasePoolPush();
#ifdef OF_WINDOWS
	OFString *path;
#endif

	_minNumberOfDotsInAbsoluteName = 1;
	_usesTCP = false;
	_configReloadInterval = 2;

#if defined(OF_WINDOWS)
# ifdef OF_HAVE_FILES
	path = [[OFWindowsRegistryKey localMachineKey]
	    stringForValue: @"DataBasePath"
		subKeyPath: @"SYSTEM\\CurrentControlSet\\Services\\"
			    @"Tcpip\\Parameters"];
	path = [path stringByAppendingPathComponent: @"hosts"];

	if (path != nil)
		[self of_parseHosts: path];
# endif

	[self of_parseNetworkParams];
#elif defined(OF_HAVE_FILES)
	[self of_parseHosts: HOSTS_PATH];
# ifdef OF_OPENBSD
	[self of_parseHosts: @"/etc/resolv.conf.tail"];
# endif

	[self of_parseResolvConf: RESOLV_CONF_PATH];
#endif

	if (_staticHosts == nil) {
		OFArray *localhost =
#ifdef OF_HAVE_IPV6
		    [OFArray arrayWithObjects: @"::1", @"127.0.0.1", nil];
#else
		    [OFArray arrayWithObject: @"127.0.0.1"];
#endif

		_staticHosts = [[OFDictionary alloc]
		    initWithObject: localhost
			    forKey: @"localhost"];
	}

	if (_nameServers == nil)
#ifdef OF_HAVE_IPV6
		_nameServers = [[OFArray alloc]
		    initWithObjects: @"127.0.0.1", @"::1", nil];
#else
		_nameServers = [[OFArray alloc] initWithObject: @"127.0.0.1"];
#endif

	if (_localDomain == nil)
		_localDomain = [domainFromHostname() copy];

	if (_searchDomains == nil) {
		if (_localDomain != nil)
			_searchDomains = [[OFArray alloc]
			    initWithObject: _localDomain];
		else
			_searchDomains = [[OFArray alloc] init];
	}

	_lastConfigReload = [[OFDate alloc] init];

	objc_autoreleasePoolPop(pool);
}

- (void)dealloc
{
	[self close];

	[_staticHosts release];
	[_nameServers release];
	[_localDomain release];
	[_searchDomains release];
	[_lastConfigReload release];
	[_IPv4Socket release];
#ifdef OF_HAVE_IPV6
	[_IPv6Socket release];
#endif
	[_queries release];

	[super dealloc];
}

#ifdef OF_HAVE_FILES
- (void)of_parseHosts: (OFString *)path
{
	void *pool = objc_autoreleasePoolPush();
	OFCharacterSet *whitespaceCharacterSet =
	    [OFCharacterSet whitespaceCharacterSet];
	OFMutableDictionary *staticHosts;
	OFFile *file;
	OFString *line;
	OFEnumerator *enumerator;
	OFMutableArray *addresses;

	@try {
		file = [OFFile fileWithPath: path
				       mode: @"r"];
	} @catch (OFOpenItemFailedException *e) {
		objc_autoreleasePoolPop(pool);
		return;
	}

	staticHosts = [OFMutableDictionary dictionary];

	while ((line = [file readLine]) != nil) {
		void *pool2 = objc_autoreleasePoolPush();
		OFArray *components, *hosts;
		size_t pos;
		OFString *address;

		pos = [line rangeOfString: @"#"].location;
		if (pos != OF_NOT_FOUND)
			line = [line substringWithRange: of_range(0, pos)];

		components = [line
		    componentsSeparatedByCharactersInSet: whitespaceCharacterSet
						 options: OF_STRING_SKIP_EMPTY];

		if ([components count] < 2) {
			objc_autoreleasePoolPop(pool2);
			continue;
		}

		address = [components firstObject];
		hosts = [components objectsInRange:
		    of_range(1, [components count] - 1)];

		for (OFString *host in hosts) {
			addresses = [staticHosts objectForKey: host];

			if (addresses == nil) {
				addresses = [OFMutableArray array];
				[staticHosts setObject: addresses
						forKey: host];
			}

			[addresses addObject: address];
		}

		objc_autoreleasePoolPop(pool2);
	}

	enumerator = [staticHosts objectEnumerator];
	while ((addresses = [enumerator nextObject]) != nil)
		[addresses makeImmutable];

	[staticHosts makeImmutable];

	[_staticHosts release];
	_staticHosts = [staticHosts copy];

	objc_autoreleasePoolPop(pool);
}

# ifndef OF_WINDOWS
- (void)of_parseResolvConf: (OFString *)path
{
	void *pool = objc_autoreleasePoolPush();
	OFCharacterSet *whitespaceCharacterSet =
	    [OFCharacterSet whitespaceCharacterSet];
	OFCharacterSet *commentCharacters = [OFCharacterSet
	    characterSetWithCharactersInString: @"#;"];
	OFMutableArray *nameServers = [[_nameServers mutableCopy] autorelease];
	OFFile *file;
	OFString *line;

	@try {
		file = [OFFile fileWithPath: path
				       mode: @"r"];
	} @catch (OFOpenItemFailedException *e) {
		objc_autoreleasePoolPop(pool);
		return;
	}

	if (nameServers == nil)
		nameServers = [OFMutableArray array];

	while ((line = [file readLine]) != nil) {
		void *pool2 = objc_autoreleasePoolPush();
		size_t pos;
		OFArray *components, *arguments;
		OFString *option;

		pos = [line indexOfCharacterFromSet: commentCharacters];
		if (pos != OF_NOT_FOUND)
			line = [line substringWithRange: of_range(0, pos)];

		components = [line
		    componentsSeparatedByCharactersInSet: whitespaceCharacterSet
						 options: OF_STRING_SKIP_EMPTY];

		if ([components count] < 2) {
			objc_autoreleasePoolPop(pool2);
			continue;
		}

		option = [components firstObject];
		arguments = [components objectsInRange:
		    of_range(1, [components count] - 1)];

		if ([option isEqual: @"nameserver"]) {
			if ([arguments count] != 1) {
				objc_autoreleasePoolPop(pool2);
				continue;
			}

			[nameServers addObject: [arguments firstObject]];
		} else if ([option isEqual: @"domain"]) {
			if ([arguments count] != 1) {
				objc_autoreleasePoolPop(pool2);
				continue;
			}

			[_localDomain release];
			_localDomain = [[arguments firstObject] copy];
		} else if ([option isEqual: @"search"]) {
			[_searchDomains release];
			_searchDomains = [arguments copy];
		} else if ([option isEqual: @"options"])
			for (OFString *argument in arguments)
				[self of_parseResolvConfOption: argument];

		objc_autoreleasePoolPop(pool2);
	}

	[nameServers makeImmutable];

	[_nameServers release];
	_nameServers = [nameServers copy];

	objc_autoreleasePoolPop(pool);
}

- (void)of_parseResolvConfOption: (OFString *)option
{
	if ([option hasPrefix: @"ndots:"]) {
		option = [option substringWithRange:
		    of_range(6, [option length] - 6)];

		@try {
			_minNumberOfDotsInAbsoluteName =
			    (size_t)[option decimalValue];
		} @catch (id e) {
			return;
		}
	} else if ([option isEqual: @"tcp"])
		_usesTCP = true;
}
# endif
#endif

#ifdef OF_WINDOWS
- (void)of_parseNetworkParams
{
	void *pool = objc_autoreleasePoolPush();
	of_string_encoding_t encoding = [OFLocale encoding];
	OFMutableArray *nameServers;
	OFString *localDomain;
	/*
	 * We need more space than FIXED_INFO in case we have more than one
	 * name server, but we also want it to be properly aligned, meaning we
	 * can't just get a buffer of bytes. Thus, we just get space for 8.
	 */
	FIXED_INFO fixedInfo[8];
	ULONG length = sizeof(fixedInfo);
	PIP_ADDR_STRING iter;

	if (GetNetworkParams(fixedInfo, &length) != ERROR_SUCCESS)
		return;

	nameServers = [OFMutableArray array];
	localDomain = [OFString stringWithCString: fixedInfo->DomainName
					 encoding: encoding];

	for (iter = &fixedInfo->DnsServerList; iter != NULL; iter = iter->Next)
		[nameServers addObject:
		    [OFString stringWithCString: iter->IpAddress.String
				       encoding: encoding]];

	if ([nameServers count] > 0) {
		[nameServers makeImmutable];
		_nameServers = [nameServers copy];
	}

	if ([localDomain length] > 0)
		_localDomain = [localDomain copy];

	objc_autoreleasePoolPop(pool);
}
#endif

- (void)of_reloadConfig
{
	/*
	 * TODO: Rather than reparsing every, check what actually changed
	 * (mtime) and only reset those.
	 */

	if (_lastConfigReload != nil && _configReloadInterval > 0 &&
	    [_lastConfigReload timeIntervalSinceNow] < _configReloadInterval)
		return;

	[_staticHosts release];
	_staticHosts = nil;

	[_nameServers release];
	_nameServers = nil;

	[_localDomain release];
	_localDomain = nil;

	[_searchDomains release];
	_searchDomains = nil;

	_minNumberOfDotsInAbsoluteName = 1;
	_usesTCP = false;
	_configReloadInterval = 2;

	[_lastConfigReload release];
	_lastConfigReload = nil;

	[self of_parseConfig];
}

- (void)asyncResolveHost: (OFString *)host
		  target: (id)target
		selector: (SEL)selector
		 context: (id)context
{
	[self asyncResolveHost: host
		   recordClass: OF_DNS_RESOURCE_RECORD_CLASS_IN
		    recordType: OF_DNS_RESOURCE_RECORD_TYPE_ALL
			target: target
		      selector: selector
		       context: context];
}

- (void)asyncResolveHost: (OFString *)host
	     recordClass: (of_dns_resource_record_class_t)recordClass
	      recordType: (of_dns_resource_record_type_t)recordType
		  target: (id)target
		selector: (SEL)selector
		 context: (id)context
{
	void *pool = objc_autoreleasePoolPush();
	OFNumber *ID;
	OFString *domainName;
	OFDNSResolverQuery *query;

	[self of_reloadConfig];

	/* Random, unused ID */
	do {
		ID = [OFNumber numberWithUInt16: (uint16_t)of_random()];
	} while ([_queries objectForKey: ID] != nil);

	if ([host hasSuffix: @"."])
		domainName = host;
	else
		/* TODO: Properly try all search domains */
		domainName = [host stringByAppendingString: @"."];

	if ([domainName UTF8StringLength] > 253)
		@throw [OFOutOfRangeException exception];

	query = [[[OFDNSResolverQuery alloc]
	    initWithHost: host
	      domainName: domainName
	     recordClass: recordClass
	      recordType: recordType
		      ID: ID
	     nameServers: _nameServers
	   searchDomains: _searchDomains
		  target: target
		selector: selector
		 context: context] autorelease];
	[_queries setObject: query
		     forKey: ID];

	[self of_sendQuery: query];

	objc_autoreleasePoolPop(pool);
}

- (void)of_sendQuery: (OFDNSResolverQuery *)query
{
	of_socket_address_t address;
	OFUDPSocket *sock;

	[query->_cancelTimer invalidate];
	[query->_cancelTimer release];
	query->_cancelTimer = nil;
	query->_cancelTimer = [[OFTimer
	    scheduledTimerWithTimeInterval: TIMEOUT
				    target: self
				  selector: @selector(of_queryWithIDTimedOut:)
				    object: query
				   repeats: false] retain];

	address = of_socket_address_parse_ip(
	    [query->_nameServers objectAtIndex: query->_nameServersIndex], 53);

	switch (address.family) {
#ifdef OF_HAVE_IPV6
	case OF_SOCKET_ADDRESS_FAMILY_IPV6:
		if (_IPv6Socket == nil) {
			_IPv6Socket = [[OFUDPSocket alloc] init];
			[_IPv6Socket bindToHost: @"::"
					   port: 0];
			[_IPv6Socket setBlocking: false];
		}

		sock = _IPv6Socket;
		break;
#endif
	case OF_SOCKET_ADDRESS_FAMILY_IPV4:
		if (_IPv4Socket == nil) {
			_IPv4Socket = [[OFUDPSocket alloc] init];
			[_IPv4Socket bindToHost: @"0.0.0.0"
					   port: 0];
			[_IPv4Socket setBlocking: false];
		}

		sock = _IPv4Socket;
		break;
	default:
		@throw [OFInvalidArgumentException exception];
	}

	[sock asyncSendBuffer: [query->_queryData items]
		       length: [query->_queryData count]
		     receiver: address
		       target: self
		     selector: @selector(of_socket:didSendBuffer:bytesSent:
				   receiver:context:exception:)
		      context: query];
}

- (void)of_queryWithIDTimedOut: (OFDNSResolverQuery *)query
{
	OFResolveHostFailedException *exception;

	if (query == nil)
		return;

	if (query->_nameServersIndex + 1 < [query->_nameServers count]) {
		query->_nameServersIndex++;
		[self of_sendQuery: query];
		return;
	}

	if (query->_attempt < ATTEMPTS) {
		query->_attempt++;
		query->_nameServersIndex = 0;
		[self of_sendQuery: query];
		return;
	}

	query = [[query retain] autorelease];
	[_queries removeObjectForKey: query->_ID];

	exception = [OFResolveHostFailedException
	    exceptionWithHost: query->_host
		  recordClass: query->_recordClass
		   recordType: query->_recordType
			error: OF_DNS_RESOLVER_ERROR_TIMEOUT];

	callback(query->_target, query->_selector, self, query->_domainName,
	    nil, nil, nil, query->_context, exception);
}

- (size_t)of_socket: (OFUDPSocket *)sock
      didSendBuffer: (void **)buffer
	  bytesSent: (size_t)bytesSent
	   receiver: (of_socket_address_t *)receiver
	    context: (OFDNSResolverQuery *)query
	  exception: (id)exception
{
	if (exception != nil) {
		query = [[query retain] autorelease];
		[_queries removeObjectForKey: query->_ID];

		callback(query->_target, query->_selector, self,
		    query->_domainName, nil, nil, nil, query->_context,
		    exception);

		return 0;
	}

	[sock asyncReceiveIntoBuffer: [self allocMemoryWithSize: 512]
			      length: 512
			      target: self
			    selector: @selector(of_socket:didReceiveIntoBuffer:
					  length:sender:context:exception:)
			     context: nil];

	return 0;
}

-      (bool)of_socket: (OFUDPSocket *)sock
  didReceiveIntoBuffer: (unsigned char *)buffer
		length: (size_t)length
		sender: (of_socket_address_t)sender
	       context: (id)context
	     exception: (id)exception
{
	OFArray *answerRecords = nil, *authorityRecords = nil;
	OFArray *additionalRecords = nil;
	OFNumber *ID;
	OFDNSResolverQuery *query;

	if (exception != nil)
		return false;

	if (length < 2)
		/* We can't get the ID to get the query. Give up. */
		return false;

	ID = [OFNumber numberWithUInt16: (buffer[0] << 8) | buffer[1]];
	query = [[[_queries objectForKey: ID] retain] autorelease];

	if (query == nil)
		return false;

	[query->_cancelTimer invalidate];
	[query->_cancelTimer release];
	query->_cancelTimer = nil;
	[_queries removeObjectForKey: ID];

	@try {
		const unsigned char *queryDataBuffer;
		size_t i;
		of_dns_resolver_error_t error;
		uint16_t numQuestions, numAnswers, numAuthorityRecords;
		uint16_t numAdditionalRecords;

		if (length < 12)
			@throw [OFTruncatedDataException exception];

		if ([query->_queryData itemSize] != 1 ||
		    [query->_queryData count] < 12)
			@throw [OFInvalidArgumentException exception];

		queryDataBuffer = [query->_queryData items];

		/* QR */
		if ((buffer[2] & 0x80) == 0)
			@throw [OFInvalidServerReplyException exception];

		/* Opcode */
		if ((buffer[2] & 0x78) != (queryDataBuffer[2] & 0x78))
			@throw [OFInvalidServerReplyException exception];

		/* TC */
		if (buffer[2] & 0x02)
			@throw [OFTruncatedDataException exception];

		/* RCODE */
		switch (buffer[3] & 0x0F) {
		case 0:
			break;
		case 1:
			error = OF_DNS_RESOLVER_ERROR_SERVER_INVALID_FORMAT;
			break;
		case 2:
			error = OF_DNS_RESOLVER_ERROR_SERVER_FAILURE;
			break;
		case 3:
			error = OF_DNS_RESOLVER_ERROR_SERVER_NAME_ERROR;
			break;
		case 4:
			error = OF_DNS_RESOLVER_ERROR_SERVER_NOT_IMPLEMENTED;
			break;
		case 5:
			error = OF_DNS_RESOLVER_ERROR_SERVER_REFUSED;
			break;
		default:
			error = OF_DNS_RESOLVER_ERROR_UNKNOWN;
			break;
		}

		if (buffer[3] & 0x0F)
			@throw [OFResolveHostFailedException
			    exceptionWithHost: query->_host
				  recordClass: query->_recordClass
				   recordType: query->_recordType
					error: error];

		numQuestions = (buffer[4] << 8) | buffer[5];
		numAnswers = (buffer[6] << 8) | buffer[7];
		numAuthorityRecords = (buffer[8] << 8) | buffer[9];
		numAdditionalRecords = (buffer[10] << 8) | buffer[11];

		i = 12;

		/*
		 * Skip over the questions - we use the ID to identify the
		 * query.
		 *
		 * TODO: Compare to our query, just in case?
		 */
		for (uint_fast16_t j = 0; j < numQuestions; j++) {
			parseName(buffer, length, &i, MAX_ALLOWED_POINTERS);
			i += 4;
		}

		answerRecords = parseSection(buffer, length, &i, numAnswers);
		authorityRecords = parseSection(buffer, length, &i,
		    numAuthorityRecords);
		additionalRecords = parseSection(buffer, length, &i,
		    numAdditionalRecords);
	} @catch (id e) {
		callback(query->_target, query->_selector, self,
		    query->_domainName, nil, nil, nil, query->_context, e);
		return false;
	}

	callback(query->_target, query->_selector, self, query->_domainName,
	    answerRecords, authorityRecords, additionalRecords,
	    query->_context, nil);

	return false;
}

- (void)close
{
	void *pool = objc_autoreleasePoolPush();
	OFEnumerator OF_GENERIC(OFDNSResolverQuery *) *enumerator;
	OFDNSResolverQuery *query;

	[_IPv4Socket cancelAsyncRequests];
	[_IPv4Socket release];
	_IPv4Socket = nil;

#ifdef OF_HAVE_IPV6
	[_IPv6Socket cancelAsyncRequests];
	[_IPv6Socket release];
	_IPv6Socket = nil;
#endif

	enumerator = [_queries objectEnumerator];
	while ((query = [enumerator nextObject]) != nil) {
		OFResolveHostFailedException *exception;

		exception = [OFResolveHostFailedException
		    exceptionWithHost: query->_host
			  recordClass: query->_recordClass
			   recordType: query->_recordType
				error: OF_DNS_RESOLVER_ERROR_CANCELED];

		callback(query->_target, query->_selector, self,
		    query->_domainName, nil, nil, nil, query->_context,
		    exception);
	}

	[_queries removeAllObjects];

	objc_autoreleasePoolPop(pool);
}
@end
