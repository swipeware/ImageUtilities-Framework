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
  
  int copyExif(const std::string& srcPath, const std::string& destPath,
               const std::string& softwareName,
               const std::vector<std::string>& exifKeysFilter,
               const std::vector<std::string>& xmpKeysFilter)
  {
    try {
      std::unique_ptr<Exiv2::Image> srcImg = Exiv2::ImageFactory::open(srcPath);
      std::unique_ptr<Exiv2::Image> destImg = Exiv2::ImageFactory::open(destPath);
      if (!srcImg || !destImg) return -1;
      
      srcImg->readMetadata();
      
      Exiv2::ExifData exifData = srcImg->exifData();
      Exiv2::XmpData xmpData = srcImg->xmpData();
      Exiv2::IptcData iptcData = srcImg->iptcData();
      
      // Remove all thumbnail metadata from exif
      for (auto iterator = exifData.begin(); iterator != exifData.end(); ) {
        if (iterator->key().find("Exif.Thumbnail") == 0) {
          iterator = exifData.erase(iterator);  // Erase and move iterator to next valid entry
        }
        else {
          ++iterator;
        }
      }
      
      // Remove all thumbnail metadata from xmp
      for (auto iterator = xmpData.begin(); iterator != xmpData.end(); ) {
        if (iterator->key().find("Xmp.Thumbnail") == 0) {
          iterator = xmpData.erase(iterator);  // Erase and move iterator to next valid entry
        }
        else {
          ++iterator;
        }
      }
      
      // Remove specified Exif keys
      for (const auto& exifKey : exifKeysFilter) {
        Exiv2::ExifKey key(exifKey);
        auto pos = exifData.findKey(key);
        if (pos != exifData.end()) {
          exifData.erase(pos);
        }
      }
      
      // Remove specified xmp keys
      for (const auto& xmpKey : xmpKeysFilter) {
        Exiv2::XmpKey key(xmpKey);
        auto pos = xmpData.findKey(key);
        if (pos != xmpData.end()) {
          xmpData.erase(pos);
        }
      }
      
      // Brand with software name
      if (!softwareName.empty()) {
        exifData["Exif.Image.Software"] = softwareName;
        if (!xmpData.empty()) {
          xmpData["Xmp.tiff.Software"] = softwareName;
        }
      }
      
      destImg->setExifData(exifData); // Replaces all EXIF metadata
      destImg->clearXmpData();        // Make sure to remove old XMP data first (merges by default)
      destImg->setXmpData(xmpData);   // Set new XMP data
      destImg->setIptcData(iptcData); // Replaces all IPTC data
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

- (int)copyExifFrom:(NSString *)srcPath
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
  
  return _privateImpl->copyExif(cppSrcPath, cppDestPath,
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
