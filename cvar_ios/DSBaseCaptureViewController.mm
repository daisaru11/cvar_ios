//
//  DSBaseCaptureViewController.m
//  cvar_ios
//
//  Created by 酒井 大地 on 2013/02/05.
//  Copyright (c) 2013年 daisaru11. All rights reserved.
//

#import "DSBaseCaptureViewController.h"

// Number of frames to average for FPS calculation
const int kFrameTimeBufferSize = 5;

@interface DSBaseCaptureViewController ()
{
}

- (BOOL)createCaptureSession:(NSInteger)camera qualityPreset:(NSString *)qualityPreset grayscale:(BOOL)grayscale;
- (void)destroyCaptureSession;

@end


@implementation DSBaseCaptureViewController

@synthesize fps = _fps;
@synthesize camera = _camera;
@synthesize captureGrayscale = _captureGrayscale;
@synthesize qualityPreset = _qualityPreset;

- (id)initWithCoder:(NSCoder *)aDecoder
{
    self = [super initWithCoder:aDecoder];
    if (self) {
        _camera = -1;
        _qualityPreset = AVCaptureSessionPresetMedium;
        _captureGrayscale = NO;
		_cnt = 0;
		
        // Create frame time circular buffer for calculating averaged fps
        _frameTimes = (float*)malloc(sizeof(float) * kFrameTimeBufferSize);
	}
    return self;
}

- (void)dealloc
{
    if (_frameTimes) {
        free(_frameTimes);
    }
}

- (void)setFps:(float)fps
{
    [self willChangeValueForKey:@"fps"];
    _fps = fps;
    [self didChangeValueForKey:@"fps"];
    
}


- (void)viewDidLoad
{
    [super viewDidLoad];
    [self createCaptureSession:_camera qualityPreset:_qualityPreset grayscale:_captureGrayscale];
    [_captureSession startRunning];
}

- (void)viewDidUnload
{
    [super viewDidUnload];
    [self destroyCaptureSession];
}

- (void)didReceiveMemoryWarning
{
    [super didReceiveMemoryWarning];
}

- (BOOL)shouldAutorotateToInterfaceOrientation:(UIInterfaceOrientation)interfaceOrientation
{
	 if (interfaceOrientation == UIDeviceOrientationLandscapeRight) {
		 return YES;
	 } else {
		 return NO;
	}
}

// Sets up the video capture session for the specified camera, quality and grayscale mode
//
//
// camera: -1 for default, 0 for back camera, 1 for front camera
// qualityPreset: [AVCaptureSession sessionPreset] value
// grayscale: YES to capture grayscale frames, NO to capture RGBA frames
//
- (BOOL)createCaptureSession:(NSInteger)camera qualityPreset:(NSString *)qualityPreset grayscale:(BOOL)grayscale
{
	_lastFrameTimestamp = 0;
	_frameTimesIndex = 0;
	_captureQueueFps = 0.0f;
	_fps = 0.0f;

	// Set up AV capture
	NSArray* devices = [AVCaptureDevice devicesWithMediaType:AVMediaTypeVideo];

	if ([devices count] == 0) {
		NSLog(@"No video capture devices found");
		return NO;
	}

	if (camera == -1) {
		_camera = -1;
		_captureDevice = [AVCaptureDevice defaultDeviceWithMediaType:AVMediaTypeVideo];
	}
	else if (camera >= 0 && camera < [devices count]) {
		_camera = camera;
		_captureDevice = [devices objectAtIndex:camera];
	}
	else {
		_camera = -1;
		_captureDevice = [AVCaptureDevice defaultDeviceWithMediaType:AVMediaTypeVideo];
		NSLog(@"Camera number out of range. Using default camera");
	}

	// Lock auto focus
	if ([_captureDevice isFocusModeSupported:AVCaptureFocusModeLocked]) {
		NSError *error = nil;
		if ([_captureDevice lockForConfiguration:&error]) {
			_captureDevice.focusMode = AVCaptureFocusModeLocked;
			[_captureDevice unlockForConfiguration];
		}
		else {
			NSLog(@"Getting error before lock the capture device");
		}
	}

	// Create the capture session
	_captureSession = [[AVCaptureSession alloc] init];
	_captureSession.sessionPreset = (qualityPreset)? qualityPreset : AVCaptureSessionPresetMedium;

	// Create device input
	NSError *error = nil;
	AVCaptureDeviceInput *input = [[AVCaptureDeviceInput alloc] initWithDevice:_captureDevice error:&error];

	// Create and configure device output
	_videoOutput = [[AVCaptureVideoDataOutput alloc] init];

	dispatch_queue_t queue = dispatch_queue_create("cameraQueue", NULL);
	[_videoOutput setSampleBufferDelegate:self queue:queue];
	//dispatch_release(queue);

	_videoOutput.alwaysDiscardsLateVideoFrames = YES;
	//_videoOutput.minFrameDuration = CMTimeMake(1, 30);


	// For grayscale mode, the luminance channel from the YUV fromat is used
	// For color mode, BGRA format is used
	OSType format = kCVPixelFormatType_32BGRA;

	// Check YUV format is available before selecting it (iPhone 3 does not support it)
	if (grayscale && [_videoOutput.availableVideoCVPixelFormatTypes containsObject:
			[NSNumber numberWithInt:kCVPixelFormatType_420YpCbCr8BiPlanarFullRange]]) {
		format = kCVPixelFormatType_420YpCbCr8BiPlanarFullRange;
	}

	_videoOutput.videoSettings = [NSDictionary dictionaryWithObject:[NSNumber numberWithUnsignedInt:format]
		forKey:(id)kCVPixelBufferPixelFormatTypeKey];

	for(AVCaptureConnection *connection in _videoOutput.connections)
	{
		if (connection.supportsVideoOrientation)
		{
			connection.videoOrientation = AVCaptureVideoOrientationLandscapeRight;
		}
		if (connection.isVideoMinFrameDurationSupported)
		{
			connection.videoMinFrameDuration = CMTimeMake(1, 15);
		}
		if (connection.isVideoMaxFrameDurationSupported)
		{
			connection.videoMaxFrameDuration = CMTimeMake(1, 30);
		}
	}

	// Connect up inputs and outputs
	if ([_captureSession canAddInput:input]) {
		[_captureSession addInput:input];
	}

	if ([_captureSession canAddOutput:_videoOutput]) {
		[_captureSession addOutput:_videoOutput];
	}


	return YES;
}

- (void)destroyCaptureSession
{
    [_captureSession stopRunning];
}

// AVCaptureVideoDataOutputSampleBufferDelegate delegate method called when a video frame is available
//
// This method is called on the video capture GCD queue. A cv::Mat is created from the frame data and
// passed on for processing with OpenCV.
- (void)captureOutput:(AVCaptureOutput *)captureOutput didOutputSampleBuffer:(CMSampleBufferRef)sampleBuffer
       fromConnection:(AVCaptureConnection *)connection
{
    CVPixelBufferRef pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer);
    OSType format = CVPixelBufferGetPixelFormatType(pixelBuffer);
    CGRect videoRect = CGRectMake(0.0f, 0.0f, CVPixelBufferGetWidth(pixelBuffer), CVPixelBufferGetHeight(pixelBuffer));
    AVCaptureVideoOrientation videoOrientation = [[[_videoOutput connections] objectAtIndex:0] videoOrientation];
    //_msg = [NSString stringWithFormat:@"cnt:%d, width: %f, height: %f", _cnt, videoRect.size.width, videoRect.size.height ];
    
    if (format == kCVPixelFormatType_420YpCbCr8BiPlanarFullRange) {
        // For grayscale mode, the luminance channel of the YUV data is used
        CVPixelBufferLockBaseAddress(pixelBuffer, 0);
        void *baseaddress = CVPixelBufferGetBaseAddressOfPlane(pixelBuffer, 0);
        
        cv::Mat mat(videoRect.size.height, videoRect.size.width, CV_8UC1, baseaddress, 0);
        
        [self processFrame:mat videoRect:videoRect videoOrientation:videoOrientation];
        
        CVPixelBufferUnlockBaseAddress(pixelBuffer, 0);
    }
    else if (format == kCVPixelFormatType_32BGRA) {
        // For color mode a 4-channel cv::Mat is created from the BGRA data
        CVPixelBufferLockBaseAddress(pixelBuffer, 0);
        void *baseaddress = (uint8_t*) CVPixelBufferGetBaseAddress(pixelBuffer);
        
		size_t bytesPerRow = CVPixelBufferGetBytesPerRow(pixelBuffer);
		
        cv::Mat mat(videoRect.size.height, videoRect.size.width, CV_8UC4, baseaddress, bytesPerRow);
		
        [self processFrame:mat videoRect:videoRect videoOrientation:videoOrientation];
        
        CVPixelBufferUnlockBaseAddress(pixelBuffer, 0);
    }
    else {
        NSLog(@"Unsupported video format");
    }
    
    // Update FPS calculation
    CMTime presentationTime = CMSampleBufferGetOutputPresentationTimeStamp(sampleBuffer);
    
    if (_lastFrameTimestamp == 0) {
        _lastFrameTimestamp = presentationTime.value;
        _framesToAverage = 1;
    }
    else {
        float frameTime = (float)(presentationTime.value - _lastFrameTimestamp) / presentationTime.timescale;
        _lastFrameTimestamp = presentationTime.value;
        
        _frameTimes[_frameTimesIndex++] = frameTime;
        
        if (_frameTimesIndex >= kFrameTimeBufferSize) {
            _frameTimesIndex = 0;
        }
        
        float totalFrameTime = 0.0f;
        for (int i = 0; i < _framesToAverage; i++) {
            totalFrameTime += _frameTimes[i];
        }
        
        float averageFrameTime = totalFrameTime / _framesToAverage;
        float fps = 1.0f / averageFrameTime;
        
        if (fabsf(fps - _captureQueueFps) > 0.1f) {
            _captureQueueFps = fps;
            [self setFps:fps];
        }
        
        _framesToAverage++;
        if (_framesToAverage > kFrameTimeBufferSize) {
            _framesToAverage = kFrameTimeBufferSize;
        }
    }
}

- (void)processFrame:(cv::Mat &)mat videoRect:(CGRect)rect videoOrientation:(AVCaptureVideoOrientation)orientation
{
	// some proccesing
}


@end
