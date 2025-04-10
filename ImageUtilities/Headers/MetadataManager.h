//
//  MetadataManager.h
//  ImageUtilities
//
//  Created by Ingemar Bergmark on 2025-03-02.
//

#ifndef MetadataManager_h
#define MetadataManager_h

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

// Public interface
@interface MetadataManager : NSObject

//// Initializers
- (instancetype)init NS_UNAVAILABLE; // Not needed as initWithError is the main initializer
- (nullable instancetype)initWithError:(NSError **)error NS_DESIGNATED_INITIALIZER NS_SWIFT_NAME(init()) ;

- (NSDictionary<NSString *, NSString *> *)getMetadata:(NSString *)filePath
                                             exiv2Ids:(NSArray<NSString *> *)tagIds;

- (int)copyMetadataFrom:(NSString *)srcPath
                     to:(NSString *)destPath
           softwareName:(nullable NSString *)softwareName
         exifKeysFilter:(NSArray<NSString *> *)exifKeysFilter
          xmpKeysFilter:(NSArray<NSString *> *)xmpKeysFilter;

- (int)copyICCProfileFrom:(NSString *)srcPath to:(NSString *)destPath;

@end

NS_ASSUME_NONNULL_END

#endif /* MetadataManager_h */
