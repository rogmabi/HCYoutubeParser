//
//  UIImage+YSImage.h
//  Folio Presenter
//
//  Created by Peter Willemsen on 1/23/13.
//  Copyright (c) 2013 Codebuffet. All rights reserved.
//

#import <UIKit/UIKit.h>

@interface UIImage (YSImage)
+ (UIImage*)imageFromView:(UIView*)view;
+ (UIImage*)imageFromView:(UIView*)view scaledToSize:(CGSize)newSize;
+ (UIImage*)imageWithImage:(UIImage*)image scaledToSize:(CGSize)newSize;
+ (UIImage *)imageWithImage:(UIImage *)image scaledToMaxWidth:(CGFloat)width maxHeight:(CGFloat)height doubleRetina:(BOOL)doubleRetina;
+ (void)videoThumbFromVideoPath:(NSString *)videoPath completion:(void (^)(UIImage *result))callback;
/**
 
 */
- (UIImage *)imageByScalingAndCroppingForSize:(CGSize)targetSize;
@end