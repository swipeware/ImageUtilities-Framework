//
//  ImageFuser.h
//  ImageUtilities
//
//  Created by Ingemar Bergmark on 2025-03-13
//

#ifndef ImageFuser_h
#define ImageFuser_h

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

// Public interface
@interface ImageFuser : NSObject

// Initializers
- (instancetype)init NS_UNAVAILABLE; // Not needed as initWithError is the main initializer
- (nullable instancetype)initWithError:(NSError **)error NS_DESIGNATED_INITIALIZER NS_SWIFT_NAME(init()) ;

- (NSInteger)fuseImagesWithInputPaths:(NSArray<NSString *> *)inputPaths
                       outputFilename:(NSString *)outputFilename
                                error:(NSError **)error;
@end

NS_ASSUME_NONNULL_END

#endif /* ImageFuser_h */
