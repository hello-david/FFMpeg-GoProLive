//
//  FRHudManager.h
//  FrontRow
//
//  Created by Jose Chen on 16/4/21.
//  Copyright © 2016年 UBNT. All rights reserved.
//

#import <Foundation/Foundation.h>
#import "FRMBPregressHUD.h"
@import UIKit;
@interface FRHudManager : NSObject
@property (readonly,getter=getManagerHidden) BOOL defaultHidden;

+ (instancetype)defaultManager;

- (void)showLoadingWithText:(NSString*)title;
- (void)showText:(NSString*)title hideAfter:(CGFloat)delay;
- (void)showText:(NSString*)title message:(NSString*)message hideAfter:(CGFloat)delay;
- (void)hide:(BOOL)bAnimate;
- (void)setHUDShowAfterTimeout:(NSTimeInterval)timeout;
@end
