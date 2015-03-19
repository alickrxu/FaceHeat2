//
//  SuperThermal.m
//  FaceHeat2
//
//  Created by Daijiro on 3/19/15.
//  Copyright (c) 2015 Alick Xu. All rights reserved.
//

#import "SuperThermal.hpp"
#import <opencv2/objdetect.hpp>
#import <opencv2/highgui/highgui_c.h>
#import <opencv2/core.hpp>
#import <opencv2/imgproc.hpp>
@implementation SuperThermal
cv::CascadeClassifier face_classifier;
const int HaarOptions = cv::CASCADE_FIND_BIGGEST_OBJECT;

- (id) init
{
    self = [super init];
    if (self != NULL) {
        NSString* faceCascadePath = [[NSBundle mainBundle] pathForResource:@"face_haar" ofType:@"xml"];
        face_classifier.load([faceCascadePath UTF8String]);
        
    }
    return self;
}




- (NSMutableArray *) findFaces:(UIImage *) image {
    NSMutableArray *detectedFaces = [NSMutableArray array];
    cv::Mat img = [self cvMatGrayFromUIImage:image];
    cv::Mat grayscaleFrame;
    cv::cvtColor(img, grayscaleFrame, CV_BGRA2BGR);

    std::vector<cv::Rect> faces;

    face_classifier.detectMultiScale(grayscaleFrame, faces, 1.1, 5, HaarOptions, cv::Size(30, 30));
    for (int i = 0; i < faces.size(); i++){
        cv::Rect rect = faces[i];
        [detectedFaces addObject:[NSValue valueWithCGRect:CGRectMake(rect.x, rect.y, rect.width, rect.height)]];
    }
    return detectedFaces;
}

- (cv::Mat)cvMatGrayFromUIImage:(UIImage *)image
{
    
    CGColorSpaceRef colorSpace = CGImageGetColorSpace(image.CGImage);
    CGFloat cols = image.size.width;
    CGFloat rows = image.size.height;
    
    cv::Mat cvMat(rows, cols, CV_8UC4); // 8 bits per component, 4 channels
    
    CGContextRef contextRef = CGBitmapContextCreate(cvMat.data,                 // Pointer to backing data
                                                    cols,                      // Width of bitmap
                                                    rows,                     // Height of bitmap
                                                    8,                          // Bits per component
                                                    cvMat.step[0],              // Bytes per row
                                                    colorSpace,                 // Colorspace
                                                    kCGImageAlphaNoneSkipLast |
                                                    kCGBitmapByteOrderDefault); // Bitmap info flags
    
    CGContextDrawImage(contextRef, CGRectMake(0, 0, cols, rows), image.CGImage);
    CGContextRelease(contextRef);
    
    return cvMat;

}
@end
