//
//  ImageFuser.mm
//  ImageUtilities
//
//  Created by Ingemar Bergmark on 2025-03-13.
//
#import <Foundation/Foundation.h>

#import "ImageFuser.h"
#include "opencv2/core.hpp"
#include "opencv2/imgproc.hpp"
#include "opencv2/imgcodecs.hpp"

// Adjustable settings
int LEVELS = 7;                  // Pyramid levels (1-8 recommended)
float exposure_weight = 1.0;       // Weight for well-exposed pixels (0-1 recommended)
float exposure_optimum = 0.5;      // Optimal exposure (0-1)
float exposure_width = 0.2;        // Exposure width (0-1)
float contrast_weight = 0;       // Weight for contrast (0-1 recommended)
float saturation_weight = 0.2;     // Weight for saturation (0-1 recommended)
float entropy_weight = 0;        // Entropy weight (0-1)
int blur_size = 5;               // Weight smoothing (odd number, typically 3-9)

namespace {

class ImageFuserPrivate {
public:
  // Function to compute Gaussian pyramid
  std::vector<cv::Mat> gaussianPyramid(const cv::Mat& img, int levels) {
    std::vector<cv::Mat> gp;
    gp.push_back(img);
    for (int i = 1; i < levels; i++) {
      cv::Mat down;
      pyrDown(gp[i - 1], down);
      gp.push_back(down);
    }
    return gp;
  }
  
  // Function to compute Laplacian pyramid
  std::vector<cv::Mat> laplacianPyramid(const std::vector<cv::Mat>& gp) {
    std::vector<cv::Mat> lp;
    lp.push_back(gp.back());
    for (int i = static_cast<int>(gp.size()) - 1; i > 0; i--) {
      cv::Mat up;
      pyrUp(gp[i], up, gp[i - 1].size());
      cv::Mat laplacian = gp[i - 1] - up;
      lp.push_back(laplacian);
    }
    return lp;
  }
  
  // Function to compute weight maps based on contrast, saturation, and exposure
  std::vector<cv::Mat> computeWeightMaps(const std::vector<cv::Mat>& images) {
    std::vector<cv::Mat> weights;
    
    for (const cv::Mat& img : images) {
      cv::Mat gray, laplacian, weight, saturation, exposure;
      
      // Convert to grayscale for contrast calculation
      cvtColor(img, gray, cv::COLOR_BGR2GRAY);
      
      // Contrast weight (Laplacian response)
      Laplacian(gray, laplacian, CV_32F);
      laplacian = abs(laplacian) * contrast_weight;
      
      // Saturation weight (per-channel standard deviation)
      cv::Mat imgFloat;
      img.convertTo(imgFloat, CV_32F);
      std::vector<cv::Mat> channels(3);
      split(imgFloat, channels);
      cv::Mat stdDev = (abs(channels[0] - channels[1]) + abs(channels[1] - channels[2]) + abs(channels[2] - channels[0])) / 3;
      saturation = stdDev * saturation_weight;
      
      // Exposure weight (preference for optimal exposure)
      cv::Mat grayF;
      gray.convertTo(grayF, CV_32F);
      float optimumPixel = exposure_optimum * 255.0;
      float widthPixel = exposure_width * 255.0;
      // Compute difference from optimal exposure
      cv::Mat diff = grayF - optimumPixel;
      // Compute element-wise square of the difference
      cv::Mat diffSquared;
      cv::pow(diff, 2.0, diffSquared);
      // Compute the exponent argument: - (diffSquared / (2 * widthPixel * widthPixel))
      cv::Mat expArg = -diffSquared / (2 * widthPixel * widthPixel);
      // Compute the exponent
      cv::Mat expo;
      cv::exp(expArg, expo);
      exposure = expo * exposure_weight;
      
      // Final weight map including entropy weight
      weight = (laplacian + saturation + exposure) * (1.0 + entropy_weight);
      GaussianBlur(weight, weight, cv::Size(blur_size, blur_size), 0, 0);
      
      weights.push_back(weight);
    }
    
    return weights;
  }
  
  // Function to blend Laplacian pyramids using weight maps
  std::vector<cv::Mat> blendLaplacianPyramids(const std::vector<std::vector<cv::Mat>>& lpImages, const std::vector<std::vector<cv::Mat>>& weightPyramids) {
    NSLog(@"blendLaplacianPyramids start");
    int levels = static_cast<int>(lpImages[0].size());
    std::vector<cv::Mat> blendedPyr;
    blendedPyr.resize(levels);
    for (int l = 0; l < levels; l++) {
        blendedPyr[l] = cv::Mat::zeros(lpImages[0][l].size(), CV_32FC3);
    }
    NSLog(@"blendLaplacianPyramids step 1");
    for (int l = 0; l < levels; l++) {
      cv::Mat sumWeights = cv::Mat::zeros(lpImages[0][l].size(), CV_32F);
      NSLog(@"blendLaplacianPyramids step 2");
      for (size_t i = 0; i < lpImages.size(); i++) {
        NSLog(@"[DEBUG] sumWeights size: %dx%d, weightPyramids[%zu][%d] size: %dx%d",
              sumWeights.cols, sumWeights.rows, i, l,
              weightPyramids[i][l].cols, weightPyramids[i][l].rows);
        
        // Check for size mismatch before addition
        if (sumWeights.size() != weightPyramids[i][l].size()) {
          NSLog(@"[ERROR] Size mismatch at level %d for image index %zu", l, i);
          // Optionally, you could handle the error here, e.g., return or adjust the matrix.
        }
        sumWeights += weightPyramids[i][l];
      }
      NSLog(@"blendLaplacianPyramids step 3");
      for (size_t i = 0; i < lpImages.size(); i++) {
        cv::Mat normalizedWeight;
        NSLog(@"blendLaplacianPyramids step 4");
        divide(weightPyramids[i][l], sumWeights + 1e-6, normalizedWeight);
        cv::Mat normalizedWeight3;
        NSLog(@"blendLaplacianPyramids step 5");
        // Convert the single-channel weight to 3 channels
        cv::cvtColor(normalizedWeight, normalizedWeight3, cv::COLOR_GRAY2BGR);
        NSLog(@"blendLaplacianPyramids step 6");
        cv::Mat blended;
        multiply(lpImages[i][l], normalizedWeight3, blended);
        NSLog(@"blendLaplacianPyramids step 7");
        blendedPyr[l] += blended;
        NSLog(@"blendLaplacianPyramids step 8");
      }
    }
    return blendedPyr;
  }
  
  // Function to reconstruct an image from Laplacian pyramid
  cv::Mat reconstructFromLaplacian(const std::vector<cv::Mat>& lp) {
    cv::Mat img = lp[0];
    for (size_t i = 1; i < lp.size(); i++) {
      pyrUp(img, img, lp[i].size());
      img += lp[i];
    }
    return img;
  }
  
  // Function to perform multi-scale exposure fusion
  cv::Mat multiScaleFusion(const std::vector<cv::Mat>& images) {
    if (images.empty()) return cv::Mat();
    NSLog(@"multiScaleFusion start");
    
    // Convert images to float format
    std::vector<cv::Mat> floatImages;
    for (const cv::Mat& img : images) {
      cv::Mat floatImg;
      img.convertTo(floatImg, CV_32FC3, 1.0 / 255.0);
      floatImages.push_back(floatImg);
    }
    
    // Compute weight maps
    std::vector<cv::Mat> weightMaps = computeWeightMaps(floatImages);
    NSLog(@"multiScaleFusion step 1");
    // Build Gaussian pyramids for weight maps
    std::vector<std::vector<cv::Mat>> weightPyramids;
    for (const cv::Mat& w : weightMaps) {
      auto gp = gaussianPyramid(w, LEVELS);
      // Reverse the Gaussian pyramid to match the Laplacian pyramid order
      std::reverse(gp.begin(), gp.end());
      weightPyramids.push_back(gp);
    }
    NSLog(@"multiScaleFusion step 2");
    // Build Laplacian pyramids for images
    std::vector<std::vector<cv::Mat>> laplacianPyramids;
    for (const cv::Mat& img : floatImages) {
      laplacianPyramids.push_back(laplacianPyramid(gaussianPyramid(img, LEVELS)));
    }
    NSLog(@"multiScaleFusion step 3");
    // Blend Laplacian pyramids using weight maps
    std::vector<cv::Mat> blendedPyr = blendLaplacianPyramids(laplacianPyramids, weightPyramids);
    NSLog(@"multiScaleFusion step 4");
    // Reconstruct final image
    cv::Mat fusedImage = reconstructFromLaplacian(blendedPyr);
    NSLog(@"multiScaleFusion step 5");
    // Convert back to 8-bit format
    fusedImage = fusedImage * 255.0;
    fusedImage.convertTo(fusedImage, CV_8UC3);
    NSLog(@"multiScaleFusion step 6");
    return fusedImage;
  }
  
  cv::Mat loadLargestTIFFImage(const std::string& filename) {
    std::vector<cv::Mat> images;
    if (!imreadmulti(filename, images, cv::IMREAD_UNCHANGED)) {
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
  
  int fuseImages(std::vector<std::string> inputPaths, const std::string& outputFilename) {
    std::vector<cv::Mat> images;
    NSLog(@"fuseImages start");
    // Load each image
    for (const std::string& path : inputPaths) {
      cv::Mat img = cv::imread(path);
      if (img.empty()) {
        return -1;// Failed to load image (file might not be a valid image)
      }
      images.push_back(img);
    }
    
    // Check that all images have the same size and number of channels
    if (!images.empty()) {
      cv::Size refSize = images[0].size();
      int refChannels = images[0].channels();
      for (size_t i = 1; i < images.size(); i++) {
        if (images[i].size() != refSize || images[i].channels() != refChannels) {
          return -1; // Inconsistent image dimensions or channel count
        }
      }
    }
    
    NSLog(@"fuseImages step 1");
    cv::Mat result = multiScaleFusion(images);
    NSLog(@"fuseImages step 2");
    imwrite(outputFilename, result);
    NSLog(@"fuseImages step 3");
    return 1;
  }
  
}; // class
} // namespace

// ====================================================================================================================

// Instance variables
@interface ImageFuser()
{
  std::unique_ptr<ImageFuserPrivate> _privateImpl;
}
@end


// Let's define the wrapper!
@implementation ImageFuser

- (nullable instancetype)initWithError:(NSError **)errorHandler {
  self = [super init];
  if (self) {
    _privateImpl = std::make_unique<ImageFuserPrivate>();
  }
  return self;
}

- (void)dealloc {
  NSLog(@"DEBUG: Successful ImageFuser dealloc");
}

- (NSInteger)fuseImagesWithInputPaths:(NSArray<NSString *> *)inputPaths
                       outputFilename:(NSString *)outputFilename
                                error:(NSError **)error {
    // Convert NSArray<NSString *> to std::vector<std::string>
    std::vector<std::string> stdInputPaths;
    for (NSString *path in inputPaths) {
        stdInputPaths.push_back(std::string([path UTF8String]));
    }
    // Convert output filename to std::string
    std::string stdOutputFilename = std::string([outputFilename UTF8String]);
    
    // Call the internal fuseImages function
    int result = _privateImpl->fuseImages(stdInputPaths, stdOutputFilename);
    
    if (result == -1 && error != nullptr) {
        *error = [NSError errorWithDomain:@"ImageFuserErrorDomain"
                                     code:result
                                 userInfo:@{NSLocalizedDescriptionKey: @"Failed to fuse images: one or more images could not be loaded."}];
    }
  
    return result;
}

@end
