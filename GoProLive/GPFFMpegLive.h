//
//  GPFFMpegLive.h
//  GoProLive
//
//  Created by David.Dai on 16/8/5.
//  Copyright © 2016年 David.Dai. All rights reserved.
//

#import <Foundation/Foundation.h>
@interface GPFFMpegLive : NSObject
@property (nonatomic,assign) BOOL pushToServer;
- (void)startLive:(NSString*)serverUrl;
- (void)stopLive;

@end
