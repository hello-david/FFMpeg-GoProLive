//
//  AACEncoder.h
//  GoProLive
//
//  Created by David.Dai on 16/8/16.
//  Copyright © 2016年 David.Dai. All rights reserved.
//

#import <Foundation/Foundation.h>
@import AudioToolbox;
@import CoreMedia;

@interface AACEncoder : NSObject

- (void) encodeSampleBuffer:(CMSampleBufferRef)sampleBuffer completionBlock:(void (^)(NSData * encodedData, NSError* error))completionBlock;

@end
