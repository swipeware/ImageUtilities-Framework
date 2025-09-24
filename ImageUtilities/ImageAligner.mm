//
//  ImageAligner.mm
//  ImageAligner
//
//  Created by Ingemar Bergmark on 2025-02-17
//

#import "ImageAligner.h"
#include "opencv2/core.hpp"
#include "opencv2/features2d.hpp"
#include "opencv2/imgproc.hpp"
#include "opencv2/imgcodecs.hpp"
#include "opencv2/calib3d.hpp"
#include "tiffio.h"


NSErrorDomain const ImageAlignerErrorDomain = @"com.swipeware.ImageAligner";

typedef NS_ERROR_ENUM(ImageAlignerErrorDomain, ImageAlignerError) {
  ImageAlignerErrorUnknown = 1,
  ImageAlignerErrorLoadReferenceFailed = 2,
  ImageAlignerErrorNotEnoughKeypoints = 3,
  ImageAlignerErrorAlignmentFailed = 4,
  ImageAlignerErrorLoadInputFailed = 5,
  ImageAlignerErrorSaveFailed = 6,
};

// Private internal class to handle OpenCV
namespace {

class ImageAlignerPrivate {
private:
  const double MIN_PIXELS = 1200; // Used for calculating scale factor
  
public:
  cv::Ptr<cv::AKAZE> akaze;
  cv::BFMatcher matcher;
  std::vector<cv::KeyPoint> refKeypoints;
  cv::Mat refDescriptors;
  cv::Size refSize;
  float scaleFactor;
  
  ImageAlignerPrivate()
    : akaze(cv::AKAZE::create()),
    matcher(cv::NORM_HAMMING, true),
    refKeypoints(),       // default-initialized (empty vector)
    refDescriptors(),     // default-initialized (empty cv::Mat)
    refSize(),            // default-initialized (width=0, height=0)
    scaleFactor(1.0f)
  {
    // Intentionally empty
  }
  
  cv::Mat getLoresTransformImageFor(const cv::Mat& inputImage) {
    cv::Mat outputImage;
    
    try {
      // Downscale the input image by the SCALEFACTOR for lores processing
      cv::resize(inputImage,
                 outputImage,
                 cv::Size(),
                 1.0 / scaleFactor,
                 1.0 / scaleFactor,
                 cv::INTER_LINEAR);
    }
    catch (const std::exception& e) {
      NSLog(@"ERROR: OpenCV resize failed: %s", e.what());
      return cv::Mat();
    }
    catch (...) {
      NSLog(@"ERROR: Unknown exception occurred in getLoresTransformImageFor");
      return cv::Mat();
    }
    
    return outputImage;
  }
  
  cv::Mat getFullscaleTransformFrom(const cv::Mat& loresTransform) {
    cv::Mat fullscaleTransform = loresTransform.clone();
    
    if (fullscaleTransform.empty() || fullscaleTransform.type() != CV_64F) {
      throw std::runtime_error("Invalid transformation matrix");
    }
    
    double* matrixData = reinterpret_cast<double*>(fullscaleTransform.data);
    
    matrixData[2] *= scaleFactor; // Scale tx
    matrixData[5] *= scaleFactor; // Scale ty
    
    return fullscaleTransform;
  }
  
  cv::Mat loadLargestTIFFImage(const std::string& filename) {
    std::vector<cv::Mat> images;
    if (!cv::imreadmulti(filename, images, cv::IMREAD_UNCHANGED)) {
      return cv::Mat(); // Return empty Mat if loading fails
    }
    
    // Find the largest image
    int maxPixels = 0;
    size_t largestIndex = 0;
    for (size_t i = 0; i < images.size(); ++i) {
      int numPixels = images[i].cols * images[i].rows;
      if (numPixels > maxPixels) {
        maxPixels = numPixels;
        largestIndex = i;
      }
    }
    
    return std::move(images[largestIndex]); // Move instead of cloning
  }
  
  void saveTIFFWithAlpha(cv::Mat image, const std::string& filename) {
    TIFF* tiffOutput = TIFFOpen(filename.c_str(), "w");
    if (!tiffOutput) return;
    
    int width = image.cols;
    int height = image.rows;
    int channels = image.channels();
    
    int bitDepth =
      (image.depth() == CV_8U) ? 8 :
      (image.depth() == CV_16U) ? 16 :
      8; // Default to 8-bit
    
    // Set TIFF metadata
    TIFFSetField(tiffOutput, TIFFTAG_IMAGEWIDTH, width);
    TIFFSetField(tiffOutput, TIFFTAG_IMAGELENGTH, height);
    TIFFSetField(tiffOutput, TIFFTAG_SAMPLESPERPIXEL, channels);
    TIFFSetField(tiffOutput, TIFFTAG_BITSPERSAMPLE, bitDepth);
    TIFFSetField(tiffOutput, TIFFTAG_PHOTOMETRIC, PHOTOMETRIC_RGB);
    TIFFSetField(tiffOutput, TIFFTAG_PLANARCONFIG, PLANARCONFIG_CONTIG);
    TIFFSetField(tiffOutput, TIFFTAG_COMPRESSION, COMPRESSION_LZW);
    TIFFSetField(tiffOutput, TIFFTAG_SAMPLEFORMAT, SAMPLEFORMAT_UINT); // Use UINT for 8-bit and 16-bit
    
    if (channels == 4) { // Has alpha channel
      uint16_t extrasample = EXTRASAMPLE_UNASSALPHA;
      TIFFSetField(tiffOutput, TIFFTAG_EXTRASAMPLES, 1, &extrasample);
    }
    
    float dpi = 300.0; // Set 300 dpi
    TIFFSetField(tiffOutput, TIFFTAG_XRESOLUTION, dpi);
    TIFFSetField(tiffOutput, TIFFTAG_YRESOLUTION, dpi);
    TIFFSetField(tiffOutput, TIFFTAG_RESOLUTIONUNIT, RESUNIT_INCH);
    
    if (bitDepth == 8) {
      std::vector<uint8_t> rowBuffer(width * channels);
      for (int y = 0; y < height; y++) {
        const uint8_t* src = image.ptr<uint8_t>(y);
        uint8_t* dst = rowBuffer.data();
        for (int x = 0; x < width; x++) {
          dst[0] = src[2]; // R
          dst[1] = src[1]; // G
          dst[2] = src[0]; // B
          if (channels == 4) {
            dst[3] = src[3]; // Alpha
          }
          src += channels;
          dst += channels;
        }
        TIFFWriteScanline(tiffOutput, rowBuffer.data(), y, 0);
      }
    }
    else if (bitDepth == 16) {
      std::vector<uint16_t> rowBuffer(width * channels);
      for (int y = 0; y < height; y++) {
        const uint16_t* src = image.ptr<uint16_t>(y);
        uint16_t* dst = rowBuffer.data();
        for (int x = 0; x < width; x++) {
          dst[0] = src[2]; // R
          dst[1] = src[1]; // G
          dst[2] = src[0]; // B
          if (channels == 4) {
            dst[3] = src[3]; // Alpha
          }
          src += channels;
          dst += channels;
        }
        TIFFWriteScanline(tiffOutput, rowBuffer.data(), y, 0);
      }
    }
    
    TIFFClose(tiffOutput);
  }
  
  void setReferenceImage(const std::string& imagePath, const std::string& outputFilePath, bool isPreview) {
    // Load the reference image in color
    cv::Mat referenceImage = loadLargestTIFFImage(imagePath);
    if (referenceImage.empty()) {
      throw std::runtime_error("Failed to load reference image.");
    }
    
    refSize.width = referenceImage.cols;
    refSize.height = referenceImage.rows;
    
    // Calculate scale factor
    int maxSide = std::max(refSize.width, refSize.height);
    scaleFactor = maxSide < MIN_PIXELS ? 1 : static_cast<int>(std::floor(static_cast<double>(maxSide) / MIN_PIXELS));
    
    // Get transformation image (downscaled if not preview)
    cv::Mat transformReference = isPreview ? referenceImage : getLoresTransformImageFor(referenceImage);
    
    // Convert to grayscale
    cv::Mat refGray;
    cv::cvtColor(transformReference, refGray, cv::COLOR_BGR2GRAY);
    
    // Detect and Compute AKAZE Keypoints and Descriptors
    refKeypoints.clear();
    refDescriptors.release();
    akaze->detectAndCompute(refGray, cv::noArray(), refKeypoints, refDescriptors);
    
    // Validate Keypoints
    if (refKeypoints.size() < 10) {
      throw std::runtime_error("Not enough keypoints detected for reliable alignment.");
    }
    
    saveTIFFWithAlpha(referenceImage, outputFilePath);
  }
  
  int getImageBitDepth(cv::Mat mat) {
    // Check Mat type to determine bit depth
    switch (mat.depth()) {
      case CV_8U:
      case CV_8S:
        return 8;
      case CV_16U:
      case CV_16S:
        return 16;
      case CV_32F:
      case CV_32S:
        return 32;
      case CV_64F:
        return 64;
      default:
        return -1; // Unknown bit depth
    }
  }
  
  void alignImage(const std::string& inputImagePath, const std::string& outputFilePath, bool isPreview) {
    cv::Mat inputImage = loadLargestTIFFImage(inputImagePath);
    if (inputImage.empty()) {
      throw std::runtime_error("Failed to load input image.");
    }
    int inputBitDepth = getImageBitDepth(inputImage);
    
    // Get transformation image and convert to grayscale
    cv::Mat transformInput = isPreview ? inputImage : getLoresTransformImageFor(inputImage);
    cv::Mat inputGray;
    cv::cvtColor(transformInput, inputGray, cv::COLOR_BGR2GRAY);
    
    // Detect and Compute AKAZE Keypoints and Descriptors
    std::vector<cv::KeyPoint> inputKeypoints;
    cv::Mat inputDescriptors;
    akaze->detectAndCompute(inputGray, cv::noArray(), inputKeypoints, inputDescriptors);
    
    // Validate Keypoints
    if (inputKeypoints.size() < 10) {
      throw std::runtime_error("Not enough keypoints detected for reliable alignment");
    }
    
    // Find matches
    std::vector<cv::DMatch> matches;
    matcher.match(refDescriptors, inputDescriptors, matches);
    
    // Sort matches and retain top 50
    std::sort(matches.begin(), matches.end(), [](const cv::DMatch& a, const cv::DMatch& b) {
      return a.distance < b.distance;
    });
    
    if (matches.size() > 50) {
      matches.resize(50);
    }
    
    // Extract Matched Points
    std::vector<cv::Point2f> refPoints, inputPoints;
    for (const auto& match : matches) {
      refPoints.push_back(refKeypoints[match.queryIdx].pt);
      inputPoints.push_back(inputKeypoints[match.trainIdx].pt);
    }
    
    // Estimate Affine Transformation
    cv::Mat inliers;
    cv::Mat loresTransform = cv::estimateAffinePartial2D(inputPoints,
                                                         refPoints,
                                                         inliers,
                                                         cv::RANSAC,
                                                         3.0,
                                                         2000,
                                                         0.99,
                                                         10);
    
    if (loresTransform.empty()) {
      throw std::runtime_error("Failed to compute a valid affine transformation");
    }
    
    // Scale transformation to full resolution if needed
    cv::Mat fullscaleTransform = isPreview ? loresTransform : getFullscaleTransformFrom(loresTransform);
    
    // Apply Affine Transformation
    cv::Mat alignedImage;
    cv::warpAffine(inputImage, alignedImage, fullscaleTransform, refSize);
    
    // Create an alpha mask
    int alphaBitDepth = inputBitDepth == 8 ? CV_8UC1 : CV_16UC1;
    int transparentBitDepth = inputBitDepth == 8 ? CV_8UC4 : CV_16UC4;
    int maskValue = (1 << inputBitDepth) - 1;
    cv::Mat referenceAlphaChannel(refSize, alphaBitDepth, maskValue);
    cv::Mat finalAlphaChannel;
    cv::warpAffine(referenceAlphaChannel, finalAlphaChannel, fullscaleTransform, refSize);
    
    // Combine the alpha channel with the aligned image
    cv::Mat transparentImage(alignedImage.size(), transparentBitDepth);
    cv::cvtColor(alignedImage, transparentImage, cv::COLOR_BGR2BGRA);
    std::vector<cv::Mat> channels;
    split(transparentImage, channels);  // Split into B, G, R, A channels
    channels[3] = finalAlphaChannel;    // Replace alpha channel
    merge(channels, transparentImage);
    
    // Save the aligned image
    saveTIFFWithAlpha(transparentImage, outputFilePath);
  }
}; // class
} // namespace

// ====================================================================================================================

// Instance variables
@interface ImageAligner()
{
  std::unique_ptr<ImageAlignerPrivate> _privateImpl;
}
@end


// Let's define the wrapper!
@implementation ImageAligner

- (nullable instancetype)initWithError:(NSError **)errorHandler {
  self = [super init];
  if (self) {
    _privateImpl = std::make_unique<ImageAlignerPrivate>();
  }
  return self;
}

- (void)dealloc {
  // Intentionally empty
}

// ImageAligner.mm
- (BOOL)setReferenceImage:(NSString*)referenceImagePath
               outputPath:(NSString*)outputPath
                isPreview:(BOOL)isPreview
                    error:(NSError **)error
{
  if (referenceImagePath.length == 0) {
    if (error) {
      *error = [NSError errorWithDomain:ImageAlignerErrorDomain
                                   code:ImageAlignerErrorLoadReferenceFailed
                               userInfo:@{ NSLocalizedDescriptionKey : @"referenceImagePath is empty." }];
    }
    return NO;
  }
  
  try {
    _privateImpl->setReferenceImage([referenceImagePath UTF8String],
                                    [outputPath UTF8String],
                                    isPreview);
    return YES;
  }
  catch (const std::exception& e) {
    if (error) {
      *error = [NSError errorWithDomain:ImageAlignerErrorDomain
                                   code:ImageAlignerErrorLoadReferenceFailed
                               userInfo:@{ NSLocalizedDescriptionKey : @(e.what()) }];
    }
    return NO;
  }
  catch (...) {
    if (error) {
      *error = [NSError errorWithDomain:ImageAlignerErrorDomain
                                   code:ImageAlignerErrorUnknown
                               userInfo:@{ NSLocalizedDescriptionKey : @"Unknown error in setReferenceImage." }];
    }
    return NO;
  }
}

- (BOOL)alignImage:(NSString*)imagePath
        outputPath:(NSString*)outputPath
         isPreview:(BOOL)isPreview
             error:(NSError **)error
{
  try {
    _privateImpl->alignImage([imagePath UTF8String],
                             [outputPath UTF8String],
                             isPreview);
    return YES;
  }
  catch (const std::runtime_error& e) {
    NSString *message = @(e.what());
    ImageAlignerError code = ImageAlignerErrorUnknown;
    
    if ([message containsString:@"Failed to load input image"]) {
      code = ImageAlignerErrorLoadInputFailed;
    }
    else if ([message containsString:@"Not enough keypoints"]) {
      code = ImageAlignerErrorNotEnoughKeypoints;
    }
    else if ([message containsString:@"affine"]) {
      code = ImageAlignerErrorAlignmentFailed;
    }
    
    if (error) {
      *error = [NSError errorWithDomain:ImageAlignerErrorDomain
                                   code:code
                               userInfo:@{ NSLocalizedDescriptionKey : message }];
    }
    return NO;
  }
  catch (const std::exception& e) {
    if (error) {
      *error = [NSError errorWithDomain:ImageAlignerErrorDomain
                                   code:ImageAlignerErrorUnknown
                               userInfo:@{ NSLocalizedDescriptionKey : @(e.what()) }];
    }
    return NO;
  }
  catch (...) {
    if (error) {
      *error = [NSError errorWithDomain:ImageAlignerErrorDomain
                                   code:ImageAlignerErrorUnknown
                               userInfo:@{ NSLocalizedDescriptionKey : @"Unknown error in alignImage." }];
    }
    return NO;
  }
}

@end
