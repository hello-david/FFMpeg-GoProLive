//
//  GPAudioLive.h
//  GoProLive
//
//  Created by David.Dai on 16/8/16.
//  Copyright © 2016年 David.Dai. All rights reserved.
//

#import <Foundation/Foundation.h>
@import AVFoundation;

@interface GPAudioLive : NSObject

- (void)stratAACAudioFromMic;
- (void)stopAACAudioFromMic;

@end
