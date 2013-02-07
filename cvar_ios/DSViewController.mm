//
//  DSViewController.m
//  cvar_ios
//
//  Created by 酒井 大地 on 2013/01/21.
//  Copyright (c) 2013年 daisaru11. All rights reserved.
//

#import "DSViewController.h"
#import "EAGLView.h"

// C/C++ interface
#include <iostream>
#include "cvmath.h"
#include "cvconvert.h"
#include "MainProcess.h"

@interface DSViewController ()
{
	// CoreMotion
	CMMotionManager *_motionManager;
    
	// OutputLayer
    AVCaptureVideoPreviewLayer *_videoPreviewLayer;
    CALayer *_outputLayer;

	EAGLView *_renderView;
    
    // Debug
    BOOL _showDebugInfo;
    UILabel *_fpsLabel;
    NSString *_msg;
    UILabel *_msgLabel;
	
	// Main Processing
	MainProcess* _tracker_process;
	
	BOOL _isTracking;
	BOOL _isInitialized;
	double _roll_offset;
	double _pitch_offset;
	double _yaw_offset;
	double _prev_attitude[3];
	double _df_attitude[3];

	BOOL _doAdjust;

	// TouchEvent value
	BOOL _isViewTouched;
	BOOL _isViewPinched;
	CGPoint _viewTouchedPoint;
	CGRect _outputBounds;
	CGFloat _pinch_scale;

}

- (BOOL)createMotionManager;
- (void)destroyMotionManager;
- (void)updateDebugInfo;
- (void)createTracker;
- (void)destroyTracker;
- (void)addGestureRecognizer;
- (void)trackingProcess:(cv::Mat&)mat;
- (CGPoint)imagePointToViewPoint:(CGPoint)imagePoint;
- (CGPoint)viewPointToImagePoint:(CGPoint)imagePoint;


@end


@implementation DSViewController

@synthesize showDebugInfo = _showDebugInfo;

- (id)initWithCoder:(NSCoder *)aDecoder
{
    self = [super initWithCoder:aDecoder];
    if (self) {
        _showDebugInfo = YES;

		_isTracking = NO;
		_isInitialized = NO;
		_isViewTouched = NO;
		_isViewPinched = NO;
		_doAdjust = NO;
		//UIImage *warp_image = [UIImage imageNamed:@"sample.jpg"];
}
    return self;
}


- (void)dealloc
{
	[self destroyTracker];
}

- (void)viewDidLoad
{
    [super viewDidLoad];
	[self createTracker];
	[self createMotionManager];
	[_motionManager startAccelerometerUpdates];
	[_motionManager startGyroUpdates];
	[_motionManager startDeviceMotionUpdates];
	[self addGestureRecognizer];
	
	if (_showDebugInfo) {
		if (!_fpsLabel) {
			// Create label to show FPS
			CGRect frame = CGRectMake(0.f, 0.f, 320.f, 25.f);
			_fpsLabel = [[UILabel alloc] initWithFrame:frame];
			_fpsLabel.textColor = [UIColor whiteColor];
			_fpsLabel.backgroundColor = [UIColor colorWithWhite:0.0f alpha:0.5f];
			[self.view addSubview:_fpsLabel];
		}
		if (!_msgLabel) {
			CGRect frame = CGRectMake(0.f, 25.f, 320.f, 25.f);
			_msgLabel = [[UILabel alloc] initWithFrame:frame];
			_msgLabel.textColor = [UIColor whiteColor];
			_msgLabel.backgroundColor = [UIColor colorWithWhite:0.0f alpha:0.5f];
			[self.view addSubview:_msgLabel];
		}
	}
}

- (void)viewDidUnload
{
    [super viewDidUnload];
	[self destroyTracker];
	[self destroyMotionManager];
}

- (void)loadView
{
    [super loadView];
}

- (void)viewWillAppear:(BOOL)animated
{
	[super viewWillAppear:animated];
}

- (void)viewDidAppear:(BOOL)animated
{
	[super viewDidAppear:animated];
	CGRect bounds = self.view.bounds;
	
	bounds.size.width = 480 * (bounds.size.height/360);
	
	// preview layer
	_videoPreviewLayer = [[AVCaptureVideoPreviewLayer alloc] initWithSession:_captureSession];
	if([_videoPreviewLayer respondsToSelector:@selector(connection)]) {
        _videoPreviewLayer.connection.videoOrientation = AVCaptureVideoOrientationLandscapeRight;
	} else {
        _videoPreviewLayer.orientation = AVCaptureVideoOrientationLandscapeRight;
	}
	[_videoPreviewLayer setFrame:bounds];
	_videoPreviewLayer.videoGravity = AVLayerVideoGravityResizeAspectFill;
	[self.view.layer insertSublayer:_videoPreviewLayer atIndex:0];
	
    // output
    _outputLayer = [CALayer layer];
    [_outputLayer setBackgroundColor:[UIColor darkGrayColor].CGColor];
    [_outputLayer setFrame:bounds];
    [self.view.layer insertSublayer:_outputLayer atIndex:0];
	
	// render view
	_renderView = [[EAGLView alloc] initWithFrame:bounds];
	[self.view addSubview:_renderView];

	_outputBounds = bounds;

}

- (void)didReceiveMemoryWarning
{
    [super didReceiveMemoryWarning];
}


- (BOOL) createMotionManager
{
	_motionManager = [[CMMotionManager alloc] init];
	
	// set up accelerometer
	if (_motionManager.accelerometerAvailable)
	{
		_motionManager.accelerometerUpdateInterval = 0.01;
	}
	else
	{
		return NO;
	}
	
	// set up gyro
	if (_motionManager.gyroAvailable)
	{
		_motionManager.gyroUpdateInterval = 0.01;
	}
	else
	{
		return NO;
	}
	
	// set up devicemotion
	if (_motionManager.deviceMotionAvailable)
	{
		_motionManager.deviceMotionUpdateInterval = 0.01;
	}
	else
	{
		return NO;
	}

	return YES;
}

- (void) destroyMotionManager
{
	if (_motionManager.accelerometerActive) {
		[_motionManager stopAccelerometerUpdates];
	}
	if (_motionManager.gyroActive)
	{
		[_motionManager stopGyroUpdates];
	}
	if (_motionManager.deviceMotionActive) {
		[_motionManager stopDeviceMotionUpdates];
	}
}

- (void)addGestureRecognizer
{
	UITapGestureRecognizer *singleFingerDTap = [[UITapGestureRecognizer alloc]
		initWithTarget:self action:@selector(handleSingleDoubleTap:)];
	singleFingerDTap.numberOfTapsRequired = 2;
	[self.view addGestureRecognizer:singleFingerDTap];
	UIPinchGestureRecognizer *pinchGesture = [[UIPinchGestureRecognizer alloc]
		initWithTarget:self action:@selector(handlePinchGesture:)];
    [self.view addGestureRecognizer:pinchGesture];
}


- (void)createTracker
{
	cv::Size map_size(2880,640);
	cv::Size img_size(480,360);

	std::vector<double> scales(2);
	scales[0] = 1.0; scales[1] = 0.5;
	std::vector<size_t> max_kp_per_cell(2);
	max_kp_per_cell[0] = 4; max_kp_per_cell[1] = 2;

	cv::Mat K = cv::Mat::eye(3,3,CV_64F);
	cv::Mat_<double> K_(K);
	//K_(0,0) = 1054;
	//K_(1,1) = 1048;
	K_(0,0) = 480;
	K_(1,1) = 480;
	K_(0,2) = 240;
	K_(1,2) = 180;
	Mat R = Mat::eye(3, 3, CV_64F);
	
	if (!_tracker_process)
	{
		_tracker_process = new MainProcess(
			//K, 1054,
			K, 480,
			map_size, img_size,
			scales,
			max_kp_per_cell
		);
	}
}

- (void) destroyTracker
{
	if (_tracker_process)
		delete _tracker_process;
}

- (void)processFrame:(cv::Mat &)mat videoRect:(CGRect)rect videoOrientation:(AVCaptureVideoOrientation)orientation
{
	_cnt++;
    //_msg = [NSString stringWithFormat:@"cnt:%d, width: %f, height: %f", _cnt, self.view.bounds.size.width, self.view.bounds.size.height ];
	__block CMAccelerometerData* accelData = _motionManager.accelerometerData;
	//_msg = [NSString stringWithFormat:@"accel: %.2f,%.2f,%.2f", accelData.acceleration.x, accelData.acceleration.y, accelData.acceleration.z];
	CMDeviceMotion* motionData = _motionManager.deviceMotion;
	
	_df_attitude[0] = (motionData.attitude.roll-_prev_attitude[0]);
	_df_attitude[1] = (motionData.attitude.pitch-_prev_attitude[1]);
	_df_attitude[2] = (motionData.attitude.yaw-_prev_attitude[2]);
	_prev_attitude[0] = motionData.attitude.roll;
	_prev_attitude[1] = motionData.attitude.pitch;
	_prev_attitude[2] = motionData.attitude.yaw;
	
	/*
	_msg = [NSString stringWithFormat:@"device: %.2f,%.2f,%.2f",
			motionData.attitude.roll/3.14*180,
			motionData.attitude.pitch/3.14*180,
			motionData.attitude.yaw/3.14*180];
	 */
	_msg = [NSString stringWithFormat:@"device: %.2f,%.2f,%.2f",
			_df_attitude[0]/3.14*180,
			_df_attitude[1]/3.14*180,
			_df_attitude[2]/3.14*180];
	
	__unsafe_unretained id _self = self;
    
    // Dispatch updating of output layer
    dispatch_sync(dispatch_get_main_queue(), ^{
		[_self trackingProcess:mat];
    });
    dispatch_sync(dispatch_get_main_queue(), ^{
        [_self updateDebugInfo];
    });
	
}

- (void)trackingProcess:(cv::Mat &)mat
{
	
	clock_t t0,t1,t2,t3;
	
	// ready resource
	cv::Mat mat_bgr, mat_rgb;
	cv::cvtColor(mat, mat_bgr, CV_BGRA2BGR);
	cv::cvtColor(mat, mat_rgb, CV_BGRA2RGB);
	
	t0 = clock();
	uint8_t* baseaddress_gray = (uint8_t*) malloc(mat_bgr.cols*mat_bgr.rows);
	neon_asm_convert_bgr(baseaddress_gray, (uint8_t *)mat_bgr.data, mat_bgr.cols*mat_bgr.rows);

	cv::Mat mat_gray(mat_bgr.rows, mat_bgr.cols, CV_8UC1, baseaddress_gray, 0);
	t1 = clock();
	

	t2 = clock();
	cv::Mat low_mat, low_mat_bgr;
	double low_scale = _tracker_process->getFrameScale(1);
	cv::Size low_size((int)(mat_bgr.cols*low_scale), (int)(mat_bgr.rows*low_scale));
	cv::resize(mat_bgr, low_mat_bgr, low_size);
	
	uint8_t* baseaddress_low_gray = (uint8_t*) malloc(low_mat_bgr.cols*low_mat_bgr.rows);
	neon_asm_convert_bgr(baseaddress_low_gray, (uint8_t *)low_mat_bgr.data, low_mat_bgr.cols*low_mat_bgr.rows);

	cv::Mat low_mat_gray(low_mat_bgr.rows, low_mat_bgr.cols, CV_8UC1, baseaddress_low_gray, 0);
	t3 = clock();
	
	//NSLog(@"grayscale: %f", (double)(t1-t0+t3-t2)/CLOCKS_PER_SEC);
	_tracker_process->setFrame(0, mat_bgr, mat_gray);
	_tracker_process->setFrame(1, low_mat_bgr, low_mat_gray);
	
	
	if (_isTracking)
	{
		// initialize
		if (!_isInitialized)
		{
			//_roll_offset = -cvmath::PI/2;
			//_pitch_offset = 0;
			//_yaw_offset = motionData.attitude.yaw;
			
			cv::Mat pose = cv::Mat::eye(3,3,CV_64F);
			//cv::Mat pose(3,3,CV_64F);
			//cv::Mat eul = (cv::Mat_<double>(1,3)
						   //<< motionData.attitude.roll - _roll_offset,
						   //motionData.attitude.yaw - _yaw_offset,
						   //-(motionData.attitude.pitch - _pitch_offset));
			//cvmath::euler2mat(eul, pose);
			
			_tracker_process->start(pose);
			_isInitialized = YES;
		}
		// pose estimation
		{
			cv::Mat df_eul = (cv::Mat_<double>(1,3)
					   << _df_attitude[0]*0.8,
						  _df_attitude[2]*0.8,
						  -_df_attitude[1]*0.8);
			cv::Mat df_pose(3,3,CV_64F);
			cvmath::euler2mat(df_eul, df_pose);
			
			_tracker_process->mulRotation(df_pose);
		}
		
		// process
		_tracker_process->process();
		
		// touched
		if (_isViewTouched)
		{
			CGPoint imagePoint = [self viewPointToImagePoint:_viewTouchedPoint];
			cv::Point2d cv_point(imagePoint.x, imagePoint.y);
			_tracker_process->findPlanar(cv_point, mat_rgb);
		}
		// pinched
		if (_isViewPinched && _tracker_process->hasTrackPoints())
		{
			_tracker_process->updatePlanar((double)_pinch_scale, mat_rgb);
		}
		// adjusting
		if (_doAdjust && _tracker_process->hasTrackPoints())
		{
			_tracker_process->adjustPlanar(mat_rgb);
		}

		if (_tracker_process->hasTrackPoints())
		{
			//cv::Point2d dst[4];
			double dst[8];
			_tracker_process->trackPointsBackProject(dst);
			[_renderView setVertices:dst];
			[_renderView drawView];
		}

	}

	// reset flags
	_isViewTouched = NO;
	_isViewPinched = NO;
	_doAdjust = NO;

	//_tracker_process->debugOutput(mat_rgb);
	
	//_outputLayer.contents = (id)[UIImage imageWithCVMat:mat_rgb].CGImage;
	//_outputLayer.contents = (id)[UIImage imageWithCVMat:_mapper->maps[1].gray].CGImage;
	
	// release
	free(baseaddress_gray);
	free(baseaddress_low_gray);
}

- (void)updateDebugInfo
{
    if (_fpsLabel) {
        _fpsLabel.text = [NSString stringWithFormat:@"FPS: %0.1f", _fps];
    }
    if (_msg && _msgLabel)
    {
        _msgLabel.text = _msg;
    }
}

- (IBAction)touchTrackBtn:(id)sender
{
	if (!_isTracking)
	{
		// start tracking
		_isTracking = YES;
		_isInitialized = NO;
		_isViewTouched = NO;
		_isViewPinched = NO;
		_doAdjust = NO;
	}
}
- (IBAction)touchAdjustBtn:(id)sender
{
	if (_isTracking)
	{
		_doAdjust = YES;
	}
}

- (IBAction)handlePinchGesture:(UITapGestureRecognizer *)recognizer
{
	_pinch_scale = [(UIPinchGestureRecognizer *)recognizer scale];
	if ([recognizer state] == UIGestureRecognizerStateEnded)
	{
		_isViewPinched = YES;
		_doAdjust = NO;
	}
}

- (IBAction)handleSingleDoubleTap:(UITapGestureRecognizer *)recognizer
{
	CGPoint touchedPoint = [recognizer locationInView:self.view];
	if ( touchedPoint.x <= _outputBounds.size.width && touchedPoint.y <= _outputBounds.size.height)
	{
		_isViewTouched = YES;
		_doAdjust = NO;
		_viewTouchedPoint = touchedPoint;
		NSLog(@"%f,%f", _viewTouchedPoint.x, _viewTouchedPoint.y);
	}
	//CGRect frame = self.view.bounds;
	//_viewTouchedPoint.x = _viewTouchedPoint.x * 480/frame.size.width;
	//_viewTouchedPoint.y = _viewTouchedPoint.y * 360/frame.size.height;
}

- (void)touchesBegan:(NSSet *)touches withEvent:(UIEvent *)event
{
	_pinch_scale = 1.0;
}

- (void)touchesEnded:(NSSet *)touches withEvent:(UIEvent *)event
{
}

- (CGPoint)imagePointToViewPoint:(CGPoint)imagePoint
{
	return CGPointMake(
		   imagePoint.x * _outputBounds.size.width/480,
		   imagePoint.y * _outputBounds.size.height );
}

- (CGPoint)viewPointToImagePoint:(CGPoint)viewPoint
{
	return CGPointMake(
		   viewPoint.x * 480/_outputBounds.size.width,
		   viewPoint.y * 320/_outputBounds.size.height );
}


@end
