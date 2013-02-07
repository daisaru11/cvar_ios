/*
     File: EAGLView.m
 Abstract: n/a
  Version: 1.2
 
 Disclaimer: IMPORTANT:  This Apple software is supplied to you by Apple
 Inc. ("Apple") in consideration of your agreement to the following
 terms, and your use, installation, modification or redistribution of
 this Apple software constitutes acceptance of these terms.  If you do
 not agree with these terms, please do not use, install, modify or
 redistribute this Apple software.
 
 In consideration of your agreement to abide by the following terms, and
 subject to these terms, Apple grants you a personal, non-exclusive
 license, under Apple's copyrights in this original Apple software (the
 "Apple Software"), to use, reproduce, modify and redistribute the Apple
 Software, with or without modifications, in source and/or binary forms;
 provided that if you redistribute the Apple Software in its entirety and
 without modifications, you must retain this notice and the following
 text and disclaimers in all such redistributions of the Apple Software.
 Neither the name, trademarks, service marks or logos of Apple Inc. may
 be used to endorse or promote products derived from the Apple Software
 without specific prior written permission from Apple.  Except as
 expressly stated in this notice, no other rights or licenses, express or
 implied, are granted by Apple herein, including but not limited to any
 patent rights that may be infringed by your derivative works or by other
 works in which the Apple Software may be incorporated.
 
 The Apple Software is provided by Apple on an "AS IS" basis.  APPLE
 MAKES NO WARRANTIES, EXPRESS OR IMPLIED, INCLUDING WITHOUT LIMITATION
 THE IMPLIED WARRANTIES OF NON-INFRINGEMENT, MERCHANTABILITY AND FITNESS
 FOR A PARTICULAR PURPOSE, REGARDING THE APPLE SOFTWARE OR ITS USE AND
 OPERATION ALONE OR IN COMBINATION WITH YOUR PRODUCTS.
 
 IN NO EVENT SHALL APPLE BE LIABLE FOR ANY SPECIAL, INDIRECT, INCIDENTAL
 OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF
 SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS
 INTERRUPTION) ARISING IN ANY WAY OUT OF THE USE, REPRODUCTION,
 MODIFICATION AND/OR DISTRIBUTION OF THE APPLE SOFTWARE, HOWEVER CAUSED
 AND WHETHER UNDER THEORY OF CONTRACT, TORT (INCLUDING NEGLIGENCE),
 STRICT LIABILITY OR OTHERWISE, EVEN IF APPLE HAS BEEN ADVISED OF THE
 POSSIBILITY OF SUCH DAMAGE.
 
 Copyright (C) 2010 Apple Inc. All Rights Reserved.
 
 */

#import <QuartzCore/QuartzCore.h>
#import <OpenGLES/EAGLDrawable.h>
#import "EAGLView.h"

//GLfloat panelVertices[] = {
//	0.0f,  0.0f, // 左上
//	0.0f,  100.0f, // 左下
//	100.0f,  0.0f, // 右上
//	100.0f, 100.0f, // 右下
//};

const GLfloat panelUVs[] = {
	0.0f, 0.0f, // 左上
	0.0f, 1.0f, // 左下
	1.0f, 0.0f, // 右上
	1.0f, 1.0f, // 右下
};
	

#define USE_DEPTH_BUFFER 0


// A class extension to declare private methods
@interface EAGLView ()

@property (nonatomic, retain) EAGLContext *context;

- (BOOL) createFramebuffer;
- (void) destroyFramebuffer;

@end


@implementation EAGLView


// You must implement this method
+ (Class)layerClass
{
    return [CAEAGLLayer class];
}


// The GL view is stored in the nib file. When it's unarchived it's sent -initWithCoder:
//- (id)initWithCoder:(NSCoder*)coder
- (id)initWithFrame:(CGRect)frame;
{    
    if ((self = [super initWithFrame:frame]))
	{
		initFlag = NO;
		double vert[8] = {0,0,0,0,0,0,0,0};
		[self setVertices:vert];
		vertUpdated = NO;
		
        // Get the layer
        CAEAGLLayer *eaglLayer = (CAEAGLLayer *)self.layer;
        eaglLayer.opaque = NO;
        eaglLayer.drawableProperties = [NSDictionary dictionaryWithObjectsAndKeys:
			[NSNumber numberWithBool:NO], kEAGLDrawablePropertyRetainedBacking,
			kEAGLColorFormatRGBA8, kEAGLDrawablePropertyColorFormat,
			nil];
			        
        context = [[EAGLContext alloc] initWithAPI:kEAGLRenderingAPIOpenGLES1];        
        if (!context || ![EAGLContext setCurrentContext:context])
		{
            return nil;
        }
        
		// Create system framebuffer object. The backing will be allocated in -reshapeFramebuffer
		glGenFramebuffersOES(1, &viewFramebuffer);
		glGenRenderbuffersOES(1, &viewRenderbuffer);
		glBindFramebufferOES(GL_FRAMEBUFFER_OES, viewFramebuffer);
		glBindRenderbufferOES(GL_RENDERBUFFER_OES, viewRenderbuffer);
		glFramebufferRenderbufferOES(GL_FRAMEBUFFER_OES, GL_COLOR_ATTACHMENT0_OES, GL_RENDERBUFFER_OES, viewRenderbuffer);
		
		// Perform additional one-time GL initialization
		//initGL();
    }
    return self;
}


- (BOOL)loadTexture:(NSString *)filename toOutput:(unsigned char**)textureData andTextureSize:(int*)pTextureSize
{
	UIImage*                image;
    CGImageRef              imageRef;
    NSUInteger              i;
    int                     textureSize;
    int                     imageWidth, imageHeight;
    NSUInteger              maxImageSize;
	CGContextRef			contextRef = nil;
	CGColorSpaceRef			colorSpace;
	BOOL					hasAlpha;
    size_t                  bitsPerComponent;
	CGImageAlphaInfo		info;
    
    image = [[UIImage alloc] initWithContentsOfFile:filename];
    if (!image) {
        NSLog(@"テクスチャファイルが開けませんでした");
        return NO;
    }
    imageRef = [image CGImage];
    
    imageWidth = CGImageGetWidth(imageRef);
    imageHeight = CGImageGetHeight(imageRef);
    if (imageWidth > imageHeight) {
        maxImageSize = imageWidth;
    } else {
        maxImageSize = imageHeight;
    }
    for (i=2; i<=1024; i*=2) {
        if (i >= maxImageSize) {
            textureSize = i;
            break;
        }
    }
    *pTextureSize = textureSize;
    
    info = CGImageGetAlphaInfo(imageRef);
    // アルファ成分があるかチェック
    hasAlpha = ((info == kCGImageAlphaPremultipliedLast) || (info == kCGImageAlphaPremultipliedFirst) || (info == kCGImageAlphaLast) || (info == kCGImageAlphaFirst) ? YES : NO);
    colorSpace = CGColorSpaceCreateDeviceRGB();
    *textureData = (unsigned char*)malloc(textureSize * textureSize * 4);
    if (!*textureData) {
        NSLog(@"メモリ確保に失敗");
        return NO;
    }
    if (hasAlpha) {
        bitsPerComponent = kCGImageAlphaPremultipliedLast;
    } else {
        bitsPerComponent = kCGImageAlphaNoneSkipLast;
    }
    contextRef = CGBitmapContextCreate(*textureData, textureSize, textureSize, 8, 4 * textureSize, colorSpace, bitsPerComponent | kCGBitmapByteOrder32Big);
    CGColorSpaceRelease(colorSpace);
    
	if((textureSize != imageWidth) || (textureSize != imageHeight)) {
        // 「画像ファイルの画像サイズ!=テクスチャのサイズ」のとき(スケーリングして使用する必要が有る場合)
		CGContextScaleCTM(contextRef, (CGFloat)textureSize/imageWidth, (CGFloat)textureSize/imageHeight);
	}
	CGContextDrawImage(contextRef, CGRectMake(0, 0, CGImageGetWidth(imageRef), CGImageGetHeight(imageRef)), imageRef);
    return YES;
}



- (void)setupView {
    glViewport(0, 0, backingWidth, backingHeight);
    glMatrixMode(GL_PROJECTION);
    glLoadIdentity();
    glOrthof(0.0f, 480.0f, 360.0f, 0.0f, -1.0f, 1.0f);
    glMatrixMode(GL_MODELVIEW);
	
	// クリア色の設定
    //glClearColor(0.0f, 0.0f, 0.0f, 1.0);
	glClearColor(0.0f, 0.0f, 0.0f, 0.0f);
	
	// テクスチャのロード
    rectTextureData = NULL;
    rectTextureName = 0;
	NSString *textureFileName = @"redbull.png";
    if ([self loadTexture:[[NSBundle mainBundle] pathForResource:textureFileName ofType:nil]
                 toOutput:(unsigned char**)&rectTextureData andTextureSize:&rectTextureSize]) {
        glGenTextures(1, &rectTextureName);
        glBindTexture(GL_TEXTURE_2D, rectTextureName);
        glTexImage2D(GL_TEXTURE_2D,
                     0,                         // MIPMAPのテクスチャ解像度(使用しないときは0)
                     GL_RGBA,                   // OpenGL内部でのピクセルデータのフォーマット
                     rectTextureSize,               // 幅
                     rectTextureSize,               // 高さ
                     0,                         // テクスチャの境界線の太さ
                     GL_RGBA,                   // メモリ上(格納前)のピクセルデータのフォーマット
                     GL_UNSIGNED_BYTE,          // メモリ上(格納前)のピクセルデータのデータ型
                     rectTextureData                // メモリ上(格納前)のピクセルデータへのポインタ
                     );
        glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_S, GL_CLAMP_TO_EDGE);    // S方向(横方向)で元のテクスチャ画像外の位置が
        // 指定されたときの処理方法
        glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_T, GL_CLAMP_TO_EDGE);    // T方向(縦方向)で元のテクスチャ画像外の位置が
        // 指定されたときの処理方法
        glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MAG_FILTER, GL_LINEAR);       // テクスチャ拡大時の補完方法を指定
        glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, GL_LINEAR);       // テクスチャ縮小時の補完方法を指定
		
		// UVの設定
        glTexCoordPointer(2, GL_FLOAT, 0, panelUVs);
        // テクスチャ座標配列の有効化
        glEnableClientState(GL_TEXTURE_COORD_ARRAY);
		glEnable(GL_TEXTURE_2D);

        glBlendFunc(GL_SRC_ALPHA, GL_ONE_MINUS_SRC_ALPHA);
        glEnable(GL_BLEND);

	}

}

- (void)setVertices:(double *)vertices
{
	panelVertices[0] = vertices[0];
	panelVertices[1] = vertices[1];
	panelVertices[2] = vertices[2];
	panelVertices[3] = vertices[3];
	panelVertices[4] = vertices[4];
	panelVertices[5] = vertices[5];
	panelVertices[6] = vertices[6];
	panelVertices[7] = vertices[7];
	vertUpdated = YES;
}


- (void)drawView
{
	if (!vertUpdated) {
		return;
	}

	// This application only creates a single GL context, so it is already current here.
	// If there are multiple contexts, ensure the correct one is current before drawing.
	//drawGL(backingWidth, backingHeight, value, mode);
	
	[EAGLContext setCurrentContext:context];
    glBindFramebufferOES(GL_FRAMEBUFFER_OES, viewFramebuffer);
	
	if(!initFlag) {
		[self setupView];
		initFlag = YES;
	}
	// 頂点配列のメモリアドレスの指定
    //glVertexPointer(3, GL_FLOAT, 0, triangleVertices);
	glVertexPointer(2, GL_FLOAT, 0, panelVertices);
    glEnableClientState(GL_VERTEX_ARRAY); // 頂点配列の有効化
	
	// カラー配列のメモリアドレスの指定
	//glColorPointer(4, GL_UNSIGNED_BYTE, 0, triangleColors);
    //glEnableClientState(GL_COLOR_ARRAY); // カラー配列の有効化

    glClear(GL_COLOR_BUFFER_BIT);
	
	glBindTexture(GL_TEXTURE_2D, rectTextureName);
	glDrawArrays(GL_TRIANGLE_STRIP,0,4);
    

	// This application only creates a single (color) renderbuffer, so it is already bound here.
	// If there are multiple renderbuffers (for example color and depth), ensure the correct one is bound here.
    [context presentRenderbuffer:GL_RENDERBUFFER_OES];
	
	vertUpdated = NO;
}


- (void)reshapeFramebuffer
{
	// Allocate GL color buffer backing, matching the current layer size
    [context renderbufferStorage:GL_RENDERBUFFER_OES fromDrawable:(CAEAGLLayer*)self.layer];
    
    glGetRenderbufferParameterivOES(GL_RENDERBUFFER_OES, GL_RENDERBUFFER_WIDTH_OES, &backingWidth);
    glGetRenderbufferParameterivOES(GL_RENDERBUFFER_OES, GL_RENDERBUFFER_HEIGHT_OES, &backingHeight);
	
	// This application only needs color. If depth and/or stencil are needed, ensure they are also resized here.
	//rt_assert(GL_FRAMEBUFFER_COMPLETE_OES == glCheckFramebufferStatusOES(GL_FRAMEBUFFER_OES));
	//glCheckError();
}

- (void)layoutSubviews {
	[super layoutSubviews];
    [EAGLContext setCurrentContext:context];
    [self destroyFramebuffer];
    [self createFramebuffer];
    [self drawView];
}

/*
- (void)layoutSubviews
{
    [self reshapeFramebuffer];
    [self drawView];
}
*/


- (BOOL)createFramebuffer {
    
    glGenFramebuffersOES(1, &viewFramebuffer);
    glGenRenderbuffersOES(1, &viewRenderbuffer);
    
    glBindFramebufferOES(GL_FRAMEBUFFER_OES, viewFramebuffer);
    glBindRenderbufferOES(GL_RENDERBUFFER_OES, viewRenderbuffer);
    [context renderbufferStorage:GL_RENDERBUFFER_OES fromDrawable:(CAEAGLLayer*)self.layer];
    glFramebufferRenderbufferOES(GL_FRAMEBUFFER_OES, GL_COLOR_ATTACHMENT0_OES, GL_RENDERBUFFER_OES, viewRenderbuffer);
    
    glGetRenderbufferParameterivOES(GL_RENDERBUFFER_OES, GL_RENDERBUFFER_WIDTH_OES, &backingWidth);
    glGetRenderbufferParameterivOES(GL_RENDERBUFFER_OES, GL_RENDERBUFFER_HEIGHT_OES, &backingHeight);
    
    if (USE_DEPTH_BUFFER) {
        glGenRenderbuffersOES(1, &depthRenderbuffer);
        glBindRenderbufferOES(GL_RENDERBUFFER_OES, depthRenderbuffer);
        glRenderbufferStorageOES(GL_RENDERBUFFER_OES, GL_DEPTH_COMPONENT16_OES, backingWidth, backingHeight);
        glFramebufferRenderbufferOES(GL_FRAMEBUFFER_OES, GL_DEPTH_ATTACHMENT_OES, GL_RENDERBUFFER_OES, depthRenderbuffer);
    }
    
    if(glCheckFramebufferStatusOES(GL_FRAMEBUFFER_OES) != GL_FRAMEBUFFER_COMPLETE_OES) {
        NSLog(@"failed to make complete framebuffer object %x", glCheckFramebufferStatusOES(GL_FRAMEBUFFER_OES));
        return NO;
    }
    
    return YES;
}


- (void)destroyFramebuffer {
    
    glDeleteFramebuffersOES(1, &viewFramebuffer);
    viewFramebuffer = 0;
    glDeleteRenderbuffersOES(1, &viewRenderbuffer);
    viewRenderbuffer = 0;
    
    if(depthRenderbuffer) {
        glDeleteRenderbuffersOES(1, &depthRenderbuffer);
        depthRenderbuffer = 0;
    }
}



- (void)dealloc
{        
    if ([EAGLContext currentContext] == context)
        [EAGLContext setCurrentContext:nil];
    
	self.context = nil;
}

@end
