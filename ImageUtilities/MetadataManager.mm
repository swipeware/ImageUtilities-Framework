//
//  MetadataManager.mm
//  ImageUtilities
//
//  Created by Ingemar Bergmark on 2025-03-02.
//

#import "MetadataManager.h"
#include "exiv2/exiv2.hpp"

// Private internal class
namespace {

class MetadataManagerPrivate {
private:
  static constexpr const char* COLORSPACE_SRGB         = "sRGB";
  static constexpr const char* COLORSPACE_ADOBE_RGB    = "Adobe RGB (1998)";
  static constexpr const char* COLORSPACE_UNCALIBRATED = "Uncalibrated";
  
  static constexpr const char* EXIV2_IMAGE_WIDTH     = "Exif.Image.ImageWidth";
  static constexpr const char* EXIV2_IMAGE_HEIGHT    = "Exif.Image.ImageLength";
  static constexpr const char* EXIV2_COLORSPACE_NAME = "ColorspaceName";

public:
  MetadataManagerPrivate() {
    // Intentionally empty
  }
  
  std::unique_ptr<Exiv2::Image> openExifFile(const std::string& imagePath) {
    try {
      auto imagePtr = Exiv2::ImageFactory::open(imagePath);
      if (!imagePtr) {
        return nullptr;
      }
      imagePtr->readMetadata();
      return imagePtr;
    }
    catch (const Exiv2::Error&) {
      return nullptr;
    }
  }
  
  std::string getExiv2Tag(const std::unique_ptr<Exiv2::Image>& imagePtr, const std::string& exiv2Id) {
    try {
      if (!imagePtr) {
        throw std::runtime_error("Invalid image pointer");
      }
      
      Exiv2::ExifData& exifData = imagePtr->exifData();
      
      // Handle special cases for image width and height
      if (exiv2Id == EXIV2_IMAGE_WIDTH) {
        return std::to_string(imagePtr->pixelWidth());
      }
      else if (exiv2Id == EXIV2_IMAGE_HEIGHT) {
        return std::to_string(imagePtr->pixelHeight());
      }
      
      // Check if the tag exists in metadata
      Exiv2::ExifKey key(exiv2Id);
      auto iter = exifData.findKey(key);
      
      if (iter != exifData.end()) {
        return iter->toString();
      }
      
      return "";
    }
    catch (const Exiv2::Error& e) {
      return "";
    }
  }

  std::string getFallbackColorSpace(const std::unique_ptr<Exiv2::Image>& imagePtr) {
    // Retrieve ColorSpace from EXIF metadata
    std::string colorSpace = getExiv2Tag(imagePtr, "Exif.Photo.ColorSpace");
    
    if (!colorSpace.empty()) {
      return (colorSpace == "1") ? COLORSPACE_SRGB : COLORSPACE_UNCALIBRATED;
    }
    
    // Check Interoperability Index as the final fallback
    std::string interopIndex = getExiv2Tag(imagePtr, "Exif.Iop.InteroperabilityIndex");
    
    return (!interopIndex.empty() && interopIndex == "R03") ? COLORSPACE_ADOBE_RGB : interopIndex;
  }
  
  std::string getIccProfileDescription(const std::unique_ptr<Exiv2::Image>& imagePtr)
  {
    const uint32_t DESC_TAG_SIGNATURE = 0x64657363; // 'desc'
    constexpr int ICC_HEADER_SIZE = 128;  // ICC Header size in bytes
    constexpr int DESC_HEADER_SIZE = 12;  // Size of the 'desc' header data
    
    try {
      if (!imagePtr) return ""; // Invalid file pointer
      
      Exiv2::DataBuf iccProfile = imagePtr->iccProfile();
      
      if (iccProfile.size() < ICC_HEADER_SIZE + 4) return ""; // Not enough data
      
      // Read tag count (big-endian)
      const uint8_t* data = iccProfile.data();
      uint32_t tagCount = Exiv2::getULong(&data[ICC_HEADER_SIZE], Exiv2::bigEndian);
      
      size_t offset = ICC_HEADER_SIZE + 4; // Start of tag table
      
      for (uint32_t i = 0; i < tagCount && offset + 12 <= iccProfile.size(); i++) {
        uint32_t tagSignature = Exiv2::getULong(&data[offset], Exiv2::bigEndian);
        uint32_t tagOffset = Exiv2::getULong(&data[offset + 4], Exiv2::bigEndian);
        uint32_t tagSize = Exiv2::getULong(&data[offset + 8], Exiv2::bigEndian);
        offset += 12;
        
        if (tagSignature == DESC_TAG_SIGNATURE) {
          // Ensure tagOffset and tagSize are within bounds
          if (tagOffset + DESC_HEADER_SIZE > iccProfile.size()) return "";
          
          // Read description length
          uint32_t dataLength = Exiv2::getULong(&data[tagOffset + 8], Exiv2::bigEndian);
          
          if (dataLength == 0 || dataLength > (tagSize - DESC_HEADER_SIZE) ||
              tagOffset + DESC_HEADER_SIZE + dataLength > iccProfile.size()) {
            return "";
          }
          
          // Extract and trim null terminators
          std::string description(reinterpret_cast<const char*>(&data[tagOffset + DESC_HEADER_SIZE]), dataLength);
          description.erase(std::find(description.begin(), description.end(), '\0'), description.end());
          
          return description; // Allocate and return
        }
      }
    }
    catch (const std::exception& e) {
      return "";
    }
    
    return "";
  }
    
  std::unordered_map<std::string, std::string> getMetadata(const std::string& filePath, const std::vector<std::string>& tagIds) {
    std::unordered_map<std::string, std::string> exifData;
        
    std::unique_ptr<Exiv2::Image> imagePtr = openExifFile(filePath);
    if (imagePtr == 0) {
      throw std::runtime_error("Failed to open EXIF file: " + filePath);
    }
    
    try {
      for (const auto& tagId : tagIds) {
        if (tagId == EXIV2_COLORSPACE_NAME) {
          std::string profileName = getIccProfileDescription(imagePtr);
          
          // Try fallback if profile name not found
          if (profileName.empty()) {
            profileName = getFallbackColorSpace(imagePtr);
          }
          
          exifData[tagId] = profileName;
        }
        else {
          exifData[tagId] = getExiv2Tag(imagePtr, tagId);
        }
      }
    }
    catch (const std::exception& e) {
      throw std::runtime_error("Error reading EXIF data: " + std::string(e.what()));
    }
    
    return exifData;
  }
  
  bool startsWithAny(const std::string& key, const std::vector<std::string>& prefixes) {
    for (const auto& prefix : prefixes) {
      if (key.rfind(prefix, 0) == 0) return true;
    }
    return false;
  }
  
  template <typename Metadata>
  void filterMetadata(Metadata& data, const std::vector<std::string>& prefixes, bool keepMatching = true) {
    for (auto it = data.begin(); it != data.end(); ) {
      bool match = startsWithAny(it->key(), prefixes);
      if ((keepMatching && !match) || (!keepMatching && match)) {
        it = data.erase(it);
      } else {
        ++it;
      }
    }
  }
  
  int copyMetadata(const std::string& srcPath, const std::string& destPath,
                   const std::string& softwareName,
                   std::vector<std::string>& exifKeysFilter,
                   std::vector<std::string>& xmpKeysFilter)
  {
    try {
      std::unique_ptr<Exiv2::Image> srcImg = Exiv2::ImageFactory::open(srcPath);
      std::unique_ptr<Exiv2::Image> destImg = Exiv2::ImageFactory::open(destPath);
      if (!srcImg || !destImg) return -1;
      
      srcImg->readMetadata();

      Exiv2::ExifData exifData = srcImg->exifData();
      Exiv2::XmpData xmpData = srcImg->xmpData();
      Exiv2::IptcData iptcData = srcImg->iptcData();
            
      // Keep only essential EXIF metadata
      std::vector<std::string> allowedExifTags = {
        "Exif.Image.Make",
        "Exif.Image.Model",
        "Exif.Photo.ExposureProgram",
        "Exif.Photo.ISOSpeedRatings",
        "Exif.Photo.SensitivityType",
        "Exif.Photo.RecommendedExposureIndex",
        "Exif.Photo.ExifVersion",
        "Exif.Photo.DateTimeOriginal",
        "Exif.Photo.DateTimeDigitized",
        "Exif.Photo.MaxApertureValue",
        "Exif.Photo.MeteringMode",
        "Exif.Photo.Flash",
        "Exif.Photo.FocalLegth",
        "Exif.Photo.ColorSpace",
        "Exif.Photo.FocalPlaneXResolution",
        "Exif.Photo.FocalPlaneYResolution",
        "Exif.Photo.FocalPlaneResolutionUnit",
        "Exif.Photo.ExposureMode",
        "Exif.Photo.WhiteBalance",
        "Exif.Photo.SceneCaptureType",
        "Exif.Photo.BodySerialNumber",
        "Exif.Photo.LensSpecification",
        "Exif.Photo.LensModel",
        "Exif.Photo.LensSerialNmber",
        "Exif.Image.UniqueCameraModel",
        "Exif.Image.CameraSerialNumber",
        "Exif.Image.LensInfo",
        "Exif.GPSInfo."
      };
      filterMetadata(exifData, allowedExifTags); // Keep tags in filter

      // Keep only essential XMP metadata
      std::vector<std::string> allowedXmpPrefixes = {
        "Xmp.dc.",
        "Xmp.photoshop.",
        "Xmp.tiff.",
        "Xmp.xmp.",
        "Xmp.xmpRights."
      };
      filterMetadata(xmpData, allowedXmpPrefixes); // Keep tags in filter

      
      // Additional XMP filters for removal to avoid metadata conficts
      std::vector<std::string> additionalXmpFilter = {
        "Xmp.tiff.Orientation", // Remove the orientation tags
        "Xmp.exif.Orientation", // as they're already used when
        "Xmp.xmp.Rotate",       // creating the processed image
        "Xmp.dc.format",
        "Xmp.xmp.ModifyDate",
        "Xmp.xmp.MetadataDate",
        "Xmp.xmp.CreatorTool"
      };
      xmpKeysFilter.insert(xmpKeysFilter.begin(), additionalXmpFilter.begin(), additionalXmpFilter.end());
      filterMetadata(xmpData, xmpKeysFilter, false); // Remove tags in filter
      
      // Additional EXIF filters for removal to avoid metadata conficts
      std::vector<std::string> additionalExifFilter = {
        "Exif.Image.Orientation" // Remove the orientation tag
      };
      exifKeysFilter.insert(exifKeysFilter.begin(), additionalExifFilter.begin(), additionalExifFilter.end());
      filterMetadata(exifData, exifKeysFilter, false); // Remove tags in filter
      
      // Brand with software name
      if (!softwareName.empty()) {
        exifData["Exif.Image.Software"] = softwareName;
        if (!xmpData.empty()) {
          xmpData["Xmp.tiff.Software"] = softwareName;
        }
      }
      
      for (Exiv2::ExifData::iterator it = exifData.begin(); it != exifData.end(); ++it) {
        // Get the key (tag) and value as std::string
        std::string key = it->key();
        std::string value = it->toString();
        NSLog(@"Key: %@", [NSString stringWithUTF8String:key.c_str()]);
      }

      for (Exiv2::XmpData::iterator it = xmpData.begin(); it != xmpData.end(); ++it) {
        // Get the key (tag) and value as std::string
        std::string key = it->key();
        std::string value = it->toString();
        NSLog(@"Key: %@", [NSString stringWithUTF8String:key.c_str()]);
      }

      destImg->setExifData(exifData);
      destImg->clearXmpData();
      destImg->setXmpData(xmpData);
      destImg->clearIptcData();
      destImg->setIptcData(iptcData);
      destImg->writeMetadata();
      
      return 1; // Success
    }
    catch (...) {
      return 0; // Error
    }
  }
  
  int copyICCProfile(const std::string& srcPath, const std::string& destPath) {
    try {
      std::unique_ptr<Exiv2::Image> srcImg = Exiv2::ImageFactory::open(srcPath);
      std::unique_ptr<Exiv2::Image> destImg = Exiv2::ImageFactory::open(destPath);
      if (!srcImg || !destImg) return -1;
      
      srcImg->readMetadata();
      destImg->readMetadata();
      
      // Check if source image has an ICC profile
      Exiv2::DataBuf iccProfile = srcImg->iccProfile();
      if (iccProfile.size() == 0) {
        return 2; // No ICC profile in source image
      }
      
      // Copy the ICC profile to destination
      destImg->setIccProfile(std::move(iccProfile));
      destImg->writeMetadata();
      
      return 1; // Success
    }
    catch (...) {
      return 0; // Error
    }
  }
  
}; // class
} // namespace

// ====================================================================================================================

// Instance variables
@interface MetadataManager()
{
  std::unique_ptr<MetadataManagerPrivate> _privateImpl;
}
@end


// Let's define the wrapper!
@implementation MetadataManager

- (nullable instancetype)initWithError:(NSError **)errorHandler {
  self = [super init];
  if (self) {
    _privateImpl = std::make_unique<MetadataManagerPrivate>();
  }
  return self;
}

- (void)dealloc {
  // Intentionally empty
}

- (NSDictionary<NSString *, NSString *> *)getMetadata:(NSString *)filePath
                                             exiv2Ids:(NSArray<NSString *> *)tagIds
{
  std::string cppFilePath = [filePath UTF8String];
  
  std::vector<std::string> cppTagIds;
  for (NSString *tag in tagIds) {
    cppTagIds.push_back([tag UTF8String]);
  }
  
  std::unordered_map<std::string, std::string> exifData = _privateImpl->getMetadata(cppFilePath, cppTagIds);
  
  NSMutableDictionary<NSString *, NSString *> *result = [NSMutableDictionary dictionary];
  for (const auto& pair : exifData) {
    NSString *key = [NSString stringWithUTF8String:pair.first.c_str()];
    NSString *value = [NSString stringWithUTF8String:pair.second.c_str()];
    result[key] = value;
  }

  return result;
}

- (int)copyMetadataFrom:(NSString *)srcPath
                     to:(NSString *)destPath
           softwareName:(nullable NSString *)softwareName
         exifKeysFilter:(NSArray<NSString *> *)exifKeysFilter
          xmpKeysFilter:(NSArray<NSString *> *)xmpKeysFilter
{
  std::string cppSrcPath = [srcPath UTF8String];
  std::string cppDestPath = [destPath UTF8String];
  std::string cppSoftwareName = softwareName ? [softwareName UTF8String] : "";
  
  std::vector<std::string> cppExifKeysFilter;
  for (NSString *key in exifKeysFilter) {
    cppExifKeysFilter.push_back([key UTF8String]);
  }
  
  std::vector<std::string> cppXmpKeysFilter;
  for (NSString *key in xmpKeysFilter) {
    cppXmpKeysFilter.push_back([key UTF8String]);
  }
  
  return _privateImpl->copyMetadata(cppSrcPath, cppDestPath,
                                    cppSoftwareName,
                                    cppExifKeysFilter,
                                    cppXmpKeysFilter);
}

- (int)copyICCProfileFrom:(NSString *)srcPath to:(NSString *)destPath {
    std::string cppSrcPath = [srcPath UTF8String];
    std::string cppDestPath = [destPath UTF8String];

    return _privateImpl->copyICCProfile(cppSrcPath, cppDestPath);
}

@end
