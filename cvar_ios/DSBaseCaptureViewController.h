//
//  DSBaseCaptureViewController.h
//  cvar_ios
//
//  Created by 酒井 大地 on 2013/02/05.
//  Copyright (c) 2013年 daisaru11. All rights reserved.
//

#import <UIKit/UIKit.h>
#import <AVFoundation/AVFoundation.h>
#import "UIImage+OpenCV.h"

@interface DSBaseCaptureViewController : UIViewController <AVCaptureVideoDataOutputSampleBufferDelegate>
{
    // AVCapture
    AVCaptureSession *_captureSession;
    AVCaptureDevice *_captureDevice;
    AVCaptureVideoDataOutput *_videoOutput;

    //
    int _camera;
    NSString *_qualityPreset;
    BOOL _captureGrayscale;

    // Fps calculation
    CMTimeValue _lastFrameTimestamp;
    float *_frameTimes;
    int _frameTimesIndex;
    int _framesToAverage;
    
    float _captureQueueFps;
    float _fps;
	int _cnt;
}

// Current frames per second
@property (readonly, assign, nonatomic) float fps;

// -1: default, 0: back camera, 1: front camera
@property (readonly, assign, nonatomic) int camera;

@property (readonly, strong, nonatomic) NSString * const qualityPreset;
@property (readonly, assign, nonatomic) BOOL captureGrayscale;

- (void)processFrame:(cv::Mat&)mat videoRect:(CGRect)rect videoOrientation:(AVCaptureVideoOrientation)orientation;

@end
