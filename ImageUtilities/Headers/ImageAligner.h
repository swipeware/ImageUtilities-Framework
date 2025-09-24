//
//  ImageAligner.h
//  ImageUtilities
//
//  Created by Ingemar Bergmark on 2025-02-17
//

#ifndef ImageAligner_h
#define ImageAligner_h

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

// Public interface
@interface ImageAligner : NSObject

// Initializers
- (instancetype)init NS_UNAVAILABLE; // Not needed as initWithError is the main initializer
- (nullable instancetype)initWithError:(NSError **)error NS_DESIGNATED_INITIALIZER NS_SWIFT_NAME(init()) ;

- (BOOL)setReferenceImage:(NSString*)referenceImagePath
               outputPath:(NSString*)outputPath
                isPreview:(BOOL)isPreview
                    error:(NSError **)error;

- (BOOL)alignImage:(NSString*)imagePath
        outputPath:(NSString*)outputPath
         isPreview:(BOOL)isPreview
             error:(NSError **)error;

@end

NS_ASSUME_NONNULL_END

#endif /* ImageAligner_h */
