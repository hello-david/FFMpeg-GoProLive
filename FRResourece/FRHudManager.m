//
//  FRHudManager.m
//
//  Created by Jose Chen on 16/4/21.
//  Copyright © 2016年 Jose Chen. All rights reserved.
//

#import "FRHudManager.h"

@interface FRHudManager ()
{
    FRMBPregressHUD  *_hud;
    UIWindow         *_window;
    NSTimer         *_showTimer;
}

@end

@implementation FRHudManager

+ (instancetype)defaultManager{
    static FRHudManager *gHudManager = nil;
    if (gHudManager == nil) {
        gHudManager = [[FRHudManager alloc] init];
    }
    return gHudManager;
}

- (instancetype)init
{
    self = [super init];
    if (self) {
        _window = [[UIApplication sharedApplication] keyWindow];
        _hud = [FRMBPregressHUD showHUDAddedTo:_window animated:YES];
        _hud.removeFromSuperViewOnHide = NO;
        _hud.detailsLabelFont = [UIFont systemFontOfSize:15*kWidthScale];
        _hud.hidden = YES;
    }
    return self;
}

- (BOOL)getManagerHidden
{
    return _hud.hidden;
}

- (void)showLoadingWithText:(NSString*)title
{
    _hud.minSize = CGSizeMake(296*kWidthScale, 116*kHeightScale);
    dispatch_async(dispatch_get_main_queue(), ^{
        _hud.mode = MBProgressHUDModeIndeterminate;
        _hud.detailsLabelText = title;
        _hud.hidden = NO;
        [_window bringSubviewToFront:_hud];
        [_hud show:NO];
    });
}

- (void)showText:(NSString*)title hideAfter:(CGFloat)delay
{
    _hud.minSize = CGSizeMake(296*kWidthScale, 76*kHeightScale);
    dispatch_async(dispatch_get_main_queue(), ^{
        _hud.mode = MBProgressHUDModeText;
        _hud.detailsLabelText = title;
        [_hud show:NO];
        _hud.hidden = NO;
        [_hud hide:YES afterDelay:delay];
    });
}

- (void)showText:(NSString*)title message:(NSString*)message hideAfter:(CGFloat)delay
{
    _hud.minSize = CGSizeMake(296*kWidthScale, 76*kHeightScale);
    dispatch_async(dispatch_get_main_queue(), ^{
        _hud.mode = MBProgressHUDModeText;
        _hud.detailsLabelText = message;
        _hud.labelText = title;
        [_hud show:NO];
        _hud.hidden = NO;
        [_window bringSubviewToFront:_hud];
        [_hud hide:YES afterDelay:delay];
    });
}

- (void)hide:(BOOL)bAnimate
{
    dispatch_async(dispatch_get_main_queue(), ^{
     [_hud hide:bAnimate];
     _hud.hidden = YES;
    });
}

- (void)setHUDShowAfterTimeout:(NSTimeInterval)timeout
{
    if(_showTimer)
    {
        [_showTimer invalidate];
        _showTimer = nil;
    }
    _hud.hidden = YES;
    _showTimer = [NSTimer scheduledTimerWithTimeInterval:timeout target:self selector:@selector(hudShowTimeout) userInfo:nil repeats:NO];
}

- (void)hudShowTimeout
{
    if(_hud.isHidden)
    {
        _hud.hidden = NO;
    }
}

@end
