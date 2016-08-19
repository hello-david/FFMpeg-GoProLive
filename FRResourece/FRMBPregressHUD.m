//
//  FRMBPregressHUD.m
//  FrontRow
//
//  Created by Jose Chen on 16/4/8.
//  Copyright © 2016年 UBNT. All rights reserved.
//

#import "FRMBPregressHUD.h"

@implementation FRMBPregressHUD

- (instancetype)initWithFrame:(CGRect)frame
{
    self = [super initWithFrame:frame];
    if (self) {
        self.backgroundColor = colorWithRGBA(000000, 0.8);
        self.detailsLabelFont = [UIFont systemFontOfSize:14];
        self.detailsLabelColor = colorWithRGB(212121);
        self.labelColor = colorWithRGB(212121);
        self.labelFont = [UIFont boldSystemFontOfSize:16];
        self.color = colorWithRGB(ffffff);
        self.activityIndicatorColor = kIndicatorColor;
        self.margin = 0;
        self.yOffset = 10;
    }
    return self;
}

@end
