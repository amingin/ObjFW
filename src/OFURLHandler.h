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

#import "OFObject.h"
#import "OFDictionary.h"
#import "OFString.h"

OF_ASSUME_NONNULL_BEGIN

/*! @file */

@class OFArray OF_GENERIC(ObjectType);
@class OFDate;
@class OFStream;
@class OFURL;

/*!
 * @brief A key for a file attribute in the file attributes dictionary.
 *
 * Possible keys for file URLs are:
 *
 *  * @ref of_file_attribute_key_size
 *  * @ref of_file_attribute_key_type
 *  * @ref of_file_attribute_key_posix_permissions
 *  * @ref of_file_attribute_key_posix_uid
 *  * @ref of_file_attribute_key_posix_gid
 *  * @ref of_file_attribute_key_owner
 *  * @ref of_file_attribute_key_group
 *  * @ref of_file_attribute_key_last_access_date
 *  * @ref of_file_attribute_key_modification_date
 *  * @ref of_file_attribute_key_status_change_date
 *  * @ref of_file_attribute_key_symbolic_link_destination
 *
 * Other URL schemes might not have all keys and might have keys not listed.
 */
typedef OFConstantString *of_file_attribute_key_t;

/*!
 * @brief The type of a file.
 *
 * Possibles values for file URLs are:
 *
 *  * @ref of_file_type_regular
 *  * @ref of_file_type_directory
 *  * @ref of_file_type_symbolic_link
 *  * @ref of_file_type_fifo
 *  * @ref of_file_type_character_special
 *  * @ref of_file_type_block_special
 *  * @ref of_file_type_socket
 *
 * Other URL schemes might not have all types and might have types not listed.
 */
typedef OFConstantString *of_file_type_t;

/*!
 * @brief A dictionary mapping keys of type @ref of_file_attribute_key_t
 *	  to their attribute values.
 */
typedef OFDictionary OF_GENERIC(of_file_attribute_key_t, id)
    *of_file_attributes_t;

/*!
 * @brief A mutable dictionary mapping keys of type
 *	  @ref of_file_attribute_key_t to their attribute values.
 */
typedef OFMutableDictionary OF_GENERIC(of_file_attribute_key_t, id)
    *of_mutable_file_attributes_t;

#ifdef __cplusplus
extern "C" {
#endif
/*!
 * @brief The size of the file as an @ref OFNumber.
 *
 * For convenience, a category on @ref OFDictionary is provided to access this
 * via @ref OFDictionary#fileSize.
 */
extern const of_file_attribute_key_t of_file_attribute_key_size;

/*!
 * @brief The type of the file.
 *
 * The corresponding value is of type @ref of_file_type_t.
 *
 * For convenience, a category on @ref OFDictionary is provided to access this
 * via @ref OFDictionary#fileType.
 */
extern const of_file_attribute_key_t of_file_attribute_key_type;

/*!
 * @brief The POSIX permissions of the file as an @ref OFNumber.
 *
 * For convenience, a category on @ref OFDictionary is provided to access this
 * via @ref OFDictionary#filePOSIXPermissions.
 */
extern const of_file_attribute_key_t of_file_attribute_key_posix_permissions;

/*!
 * @brief The POSIX UID of the file as an @ref OFNumber.
 *
 * For convenience, a category on @ref OFDictionary is provided to access this
 * via @ref OFDictionary#filePOSIXUID.
 */
extern const of_file_attribute_key_t of_file_attribute_key_posix_uid;

/*!
 * @brief The POSIX GID of the file as an @ref OFNumber.
 *
 * For convenience, a category on @ref OFDictionary is provided to access this
 * via @ref OFDictionary#filePOSIXGID.
 */
extern const of_file_attribute_key_t of_file_attribute_key_posix_gid;

/*!
 * @brief The owner of the file as an @ref OFString.
 *
 * For convenience, a category on @ref OFDictionary is provided to access this
 * via @ref OFDictionary#fileOwner.
 */
extern const of_file_attribute_key_t of_file_attribute_key_owner;

/*!
 * @brief The group of the file as an @ref OFString.
 *
 * For convenience, a category on @ref OFDictionary is provided to access this
 * via @ref OFDictionary#fileGroup.
 */
extern const of_file_attribute_key_t of_file_attribute_key_group;

/*!
 * @brief The last access date of the file as an @ref OFDate.
 *
 * For convenience, a category on @ref OFDictionary is provided to access this
 * via @ref OFDictionary#fileLastAccessDate.
 */
extern const of_file_attribute_key_t of_file_attribute_key_last_access_date;

/*!
 * @brief The last modification date of the file as an @ref OFDate.
 *
 * For convenience, a category on @ref OFDictionary is provided to access this
 * via @ref OFDictionary#fileModificationDate.
 */
extern const of_file_attribute_key_t of_file_attribute_key_modification_date;

/*!
 * @brief The last status change date of the file as an @ref OFDate.
 *
 * For convenience, a category on @ref OFDictionary is provided to access this
 * via @ref OFDictionary#fileStatusChangeDate.
 */
extern const of_file_attribute_key_t of_file_attribute_key_status_change_date;

/*!
 * @brief The destination of a symbolic link as an @ref OFString.
 *
 * For convenience, a category on @ref OFDictionary is provided to access this
 * via @ref OFDictionary#fileSymbolicLinkDestination.
 */
extern const of_file_attribute_key_t
    of_file_attribute_key_symbolic_link_destination;

/*!
 * @brief A regular file.
 */
extern const of_file_type_t of_file_type_regular;

/*!
 * @brief A directory.
 */
extern const of_file_type_t of_file_type_directory;

/*!
 * @brief A symbolic link.
 */
extern const of_file_type_t of_file_type_symbolic_link;

/*!
 * @brief A FIFO.
 */
extern const of_file_type_t of_file_type_fifo;

/*!
 * @brief A character special file.
 */
extern const of_file_type_t of_file_type_character_special;

/*!
 * @brief A block special file.
 */
extern const of_file_type_t of_file_type_block_special;

/*!
 * @brief A socket.
 */
extern const of_file_type_t of_file_type_socket;
#ifdef __cplusplus
}
#endif

/*!
 * @class OFURLHandler OFURLHandler.h ObjFW/OFURLHandler.h
 *
 * @brief A handler for a URL scheme.
 */
@interface OFURLHandler: OFObject
{
	OFString *_scheme;
}

/*!
 * @brief The scheme this OFURLHandler handles.
 */
@property (readonly, nonatomic) OFString *scheme;

/*!
 * @brief Registers the specified class as the handler for the specified scheme.
 *
 * If the same class is specified for two schemes, one instance of it is
 * created per scheme.
 *
 * @param class_ The class to register as the handler for the specified scheme
 * @param scheme The scheme for which to register the handler
 * @return Whether the class was successfully registered. If a handler for the
 *	   same scheme is already registered, registration fails.
 */
+ (bool)registerClass: (Class)class_
	    forScheme: (OFString *)scheme;

/*!
 * @brief Returns the handler for the specified URL.
 *
 * @return The handler for the specified URL.
 */
+ (nullable OF_KINDOF(OFURLHandler *))handlerForURL: (OFURL *)URL;

- (instancetype)init OF_UNAVAILABLE;

/*!
 * @brief Initializes the handler for the specified scheme.
 *
 * @param scheme The scheme to initialize for
 * @return An initialized URL handler
 */
- (instancetype)initWithScheme: (OFString *)scheme OF_DESIGNATED_INITIALIZER;

/*!
 * @brief Opens the item at the specified URL.
 *
 * @param URL The URL of the item which should be opened
 * @param mode The mode in which the file should be opened.@n
 *	       Possible modes are:
 *	       @n
 *	       Mode           | Description
 *	       ---------------|-------------------------------------
 *	       `r`            | Read-only
 *	       `r+`           | Read-write
 *	       `w`            | Write-only, create or truncate
 *	       `wx`           | Write-only, create or fail, exclusive
 *	       `w+`           | Read-write, create or truncate
 *	       `w+x`          | Read-write, create or fail, exclusive
 *	       `a`            | Write-only, create or append
 *	       `a+`           | Read-write, create or append
 *	       @n
 *	       The handler is allowed to not implement all modes and is also
 *	       allowed to implement additional, scheme-specific modes.
 */
- (OFStream *)openItemAtURL: (OFURL *)URL
		       mode: (OFString *)mode;

/*!
 * @brief Returns the attributes for the item at the specified URL.
 *
 * @param URL The URL to return the attributes for
 * @return A dictionary of attributes for the specified URL, with the keys of
 *	   type @ref of_file_attribute_key_t
 */
- (of_file_attributes_t)attributesOfItemAtURL: (OFURL *)URL;

/*!
 * @brief Sets the attributes for the item at the specified URL.
 *
 * All attributes not part of the dictionary are left unchanged.
 *
 * @param attributes The attributes to set for the specified URL
 * @param URL The URL of the item to set the attributes for
 */
- (void)setAttributes: (of_file_attributes_t)attributes
	  ofItemAtURL: (OFURL *)URL;

/*!
 * @brief Checks whether a file exists at the specified URL.
 *
 * @param URL The URL to check
 * @return A boolean whether there is a file at the specified URL
 */
- (bool)fileExistsAtURL: (OFURL *)URL;

/*!
 * @brief Checks whether a directory exists at the specified URL.
 *
 * @param URL The URL to check
 * @return A boolean whether there is a directory at the specified URL
 */
- (bool)directoryExistsAtURL: (OFURL *)URL;

/*!
 * @brief Creates a directory at the specified URL.
 *
 * @param URL The URL of the directory to create
 */
- (void)createDirectoryAtURL: (OFURL *)URL;

/*!
 * @brief Returns an array with the items in the specified directory.
 *
 * @note `.` and `..` are not part of the returned array.
 *
 * @param URL The URL to the directory whose items should be returned
 * @return An array of OFString with the items in the specified directory
 */
- (OFArray OF_GENERIC(OFString *) *)contentsOfDirectoryAtURL: (OFURL *)URL;

/*!
 * @brief Removes the item at the specified URL.
 *
 * If the item at the specified URL is a directory, it is removed recursively.
 *
 * @param URL The URL to the item which should be removed
 */
- (void)removeItemAtURL: (OFURL *)URL;

/*!
 * @brief Creates a hard link for the specified item.
 *
 * The destination URL must have a full path, which means it must include the
 * name of the item.
 *
 * This method is not available for all URLs.
 *
 * @param source The URL to the item for which a link should be created
 * @param destination The URL to the item which should link to the source
 */
- (void)linkItemAtURL: (OFURL *)source
		toURL: (OFURL *)destination;

/*!
 * @brief Creates a symbolic link for an item.
 *
 * The destination uRL must have a full path, which means it must include the
 * name of the item.
 *
 * This method is not available for all URLs.
 *
 * @note On Windows, this requires at least Windows Vista and administrator
 *	 privileges!
 *
 * @param URL The URL to the item which should symbolically link to the target
 * @param target The target of the symbolic link
 */
- (void)createSymbolicLinkAtURL: (OFURL *)URL
	    withDestinationPath: (OFString *)target;

/*!
 * @brief Tries to efficiently copy an item. If a copy would only be possible
 *	  by reading the entire item and then writing it, it returns false.
 *
 * The destination URL must have a full path, which means it must include the
 * name of the item.
 *
 * If an item already exists, the copy operation fails. This is also the case
 * if a directory is copied and an item already exists in the destination
 * directory.
 *
 * @param source The file, directory or symbolic link to copy
 * @param destination The destination URL
 * @return True if an efficient copy was performed, false if an efficient copy
 *	   was not possible. Note that errors while performing a copy are
 *	   reported via exceptions and not by returning false!
 */
- (bool)copyItemAtURL: (OFURL *)source
		toURL: (OFURL *)destination;

/*!
 * @brief Tries to efficiently move an item. If a move would only be possible
 *	  by copying the source and deleting it, it returns false.
 *
 * The destination URL must have a full path, which means it must include the
 * name of the item.
 *
 * If the destination is on a different logical device or uses a different
 * scheme, an efficient move is not possible and false is returned.
 *
 * @param source The item to rename
 * @param destination The new name for the item
 * @return True if an efficient move was performed, false if an efficient move
 *	   was not possible. Note that errors while performing a move are
 *	   reported via exceptions and not by returning false!
 */
- (bool)moveItemAtURL: (OFURL *)source
		toURL: (OFURL *)destination;
@end

@interface OFDictionary (FileAttributes)
/*!
 * The @ref of_file_attribute_key_size key from the dictionary.
 *
 * Raises an @ref OFUndefinedKeyException if the key is missing.
 */
@property (readonly, nonatomic) uintmax_t fileSize;

/*!
 * The @ref of_file_attribute_key_type key from the dictionary.
 *
 * Raises an @ref OFUndefinedKeyException if the key is missing.
 */
@property (readonly, nonatomic) of_file_type_t fileType;

/*!
 * The @ref of_file_attribute_key_posix_permissions key from the dictionary.
 *
 * Raises an @ref OFUndefinedKeyException if the key is missing.
 */
@property (readonly, nonatomic) uint16_t filePOSIXPermissions;

/*!
 * The @ref of_file_attribute_key_posix_uid key from the dictionary.
 *
 * Raises an @ref OFUndefinedKeyException if the key is missing.
 */
@property (readonly, nonatomic) uint32_t filePOSIXUID;

/*!
 * The @ref of_file_attribute_key_posix_gid key from the dictionary.
 *
 * Raises an @ref OFUndefinedKeyException if the key is missing.
 */
@property (readonly, nonatomic) uint32_t filePOSIXGID;

/*!
 * The @ref of_file_attribute_key_owner key from the dictionary.
 *
 * Raises an @ref OFUndefinedKeyException if the key is missing.
 */
@property (readonly, nonatomic) OFString *fileOwner;

/*!
 * The @ref of_file_attribute_key_group key from the dictionary.
 *
 * Raises an @ref OFUndefinedKeyException if the key is missing.
 */
@property (readonly, nonatomic) OFString *fileGroup;

/*!
 * The @ref of_file_attribute_key_last_access_date key from the dictionary.
 *
 * Raises an @ref OFUndefinedKeyException if the key is missing.
 */
@property (readonly, nonatomic) OFDate *fileLastAccessDate;

/*!
 * The @ref of_file_attribute_key_modification_date key from the dictionary.
 *
 * Raises an @ref OFUndefinedKeyException if the key is missing.
 */
@property (readonly, nonatomic) OFDate *fileModificationDate;

/*!
 * The @ref of_file_attribute_key_status_change_date key from the dictionary.
 *
 * Raises an @ref OFUndefinedKeyException if the key is missing.
 */
@property (readonly, nonatomic) OFDate *fileStatusChangeDate;

/*!
 * The @ref of_file_attribute_key_symbolic_link_destination key from the
 * dictionary.
 *
 * Raises an @ref OFUndefinedKeyException if the key is missing.
 */
@property (readonly, nonatomic) OFString *fileSymbolicLinkDestination;
@end

OF_ASSUME_NONNULL_END
