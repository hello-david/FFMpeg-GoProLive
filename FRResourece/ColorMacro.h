//
//  ColorMacro.h
//
//  Created by Jose Chen on 16/3/29.
//  Copyright © 2016年 Jose Chen. All rights reserved.
//

//通用颜色宏
// 颜色定义
//参数格式为：FFFFFF
#define colorWithRGB(rgbValue)  colorWithRGBA(rgbValue, 1.0)

//参数格式为：FFFFFF, 1.0
#define colorWithRGBA(rgbValue, alphaValue) \
[UIColor colorWithRed:((float)((0x##rgbValue & 0xFF0000) >> 16)) / 255.0 \
green:((float)((0x##rgbValue & 0xFF00) >> 8)) / 255.0 \
blue:((float)(0x##rgbValue & 0xFF)) / 255.0 alpha:alphaValue]


//主色调
#define kMainColor    colorWithRGB(0db9b3)
#define kButtonColor  colorWithRGB(09aca7)


#define kIndicatorColor colorWithRGB(36a9e1)

//通用按钮选中颜色
#define kButtonHighlightColor colorWithRGB(0085B9)

