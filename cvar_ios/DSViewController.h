//
//  DSViewController.h
//  cvar_ios
//
//  Created by 酒井 大地 on 2013/01/21.
//  Copyright (c) 2013年 daisaru11. All rights reserved.
//

#import <UIKit/UIKit.h>
#import <CoreMotion/CoreMotion.h>
#import "DSBaseCaptureViewController.h"

@interface DSViewController : DSBaseCaptureViewController
{
}
- (IBAction)touchTrackBtn:(id)sender;
- (IBAction)touchAdjustBtn:(id)sender;
- (IBAction)handlePinchGesture:(UITapGestureRecognizer *)recognizer;
- (IBAction)handleSingleDoubleTap:(UITapGestureRecognizer *)recognizer;


@property (assign, nonatomic) BOOL showDebugInfo;

@end

