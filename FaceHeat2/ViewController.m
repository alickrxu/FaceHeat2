//
//  ViewController.m
//  FaceHeatIOS
//
//  Created by Alick, Daijiro on 2/19/15.
//  Copyright (c) 2015 Team3. All rights reserved.
//

#import "ViewController.h"

@interface ViewController ()

//The main viewfinder for the FLIR ONE
@property (weak, nonatomic) IBOutlet UIImageView *visualYCBView;
@property (weak, nonatomic) IBOutlet UIImageView *thermalView;

// face feature properties
@property (strong, nonatomic) CIDetector *facedetector;
@property (strong, nonatomic) NSArray * faceFeatures;

@property (strong, nonatomic) NSData *thermalData;
@property (nonatomic) CGSize thermalSize;

@property (strong, nonatomic) NSData *visualData;
@property (nonatomic) CGSize visualSize;

//FLIR data for UI to display
@property (strong, nonatomic) UIImage *visualYCbCrImage;
@property (strong, nonatomic) UIImage *radiometricImage;


@property (nonatomic) FLIROneSDKTuningState tuningState; //tuning state of the FLIR
@property (nonatomic) BOOL connected; //determines if FLIR is connected to the phone
@property (nonatomic) FLIROneSDKImageOptions options; //options for the FLIR stream

@property (strong, nonatomic) dispatch_queue_t renderQueue; //queue for rendering


//for fps measurement (frames per second)
@property (nonatomic) NSTimeInterval lastTime;
@property (nonatomic) CGFloat fps;
@property (nonatomic) NSInteger frameCount;

@property (nonatomic) NSDictionary *imgOption; //for face detector

@property (nonatomic) NSMutableDictionary *foreheadCheekPositions; // (thermal) coordinates of forehead and cheek
@property (nonatomic) NSMutableDictionary *tempPoints; //forehead, left cheek, right cheek temperatures

@property (nonatomic) BOOL foreheadSet;

@end

@implementation ViewController


- (void)viewDidLoad {
    [super viewDidLoad];
    // Do any additional setup after loading the view, typically from a nib.
    
    //set options for the FLIR one
    self.options = FLIROneSDKImageOptionsThermalRadiometricKelvinImage | FLIROneSDKImageOptionsVisualYCbCr888Image;
    
    //create a queue for rendering
    self.renderQueue = dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0);
    
    //set content mode
    self.visualYCBView.contentMode = UIViewContentModeScaleAspectFit;
    self.thermalView.contentMode = UIViewContentModeScaleAspectFit;
    
    self.imgOption = @{CIDetectorImageOrientation: @8};
    
    NSDictionary *detectoroptions = @{ CIDetectorAccuracy : CIDetectorAccuracyLow, CIDetectorTracking: @YES};
    self.facedetector = [CIDetector detectorOfType:CIDetectorTypeFace context:nil options:detectoroptions];
    
    // add view controller to FLIR stream manager delegates
    [[FLIROneSDKStreamManager sharedInstance] addDelegate:self];
    [[FLIROneSDKStreamManager sharedInstance] setImageOptions: self.options];
    self.faceFeatures = @[];
    
    //initialize dictionaries
    self.tempPoints = [NSMutableDictionary dictionary];
    self.foreheadCheekPositions = [NSMutableDictionary dictionary];
    
    self.foreheadSet = NO;
    
    //disable locking of the screen
    [[UIApplication sharedApplication] setIdleTimerDisabled:YES];
    //update UI here
}


- (void)didReceiveMemoryWarning {
    [super didReceiveMemoryWarning];
    // Dispose of any resources that can be recreated.
}

- (void) FLIROneSDKDidConnect {
    self.connected = YES;
    
    self.frameCount = 0; //initialize frameCount
    [self updateUI];
}

- (void) FLIROneSDKDidDisconnect {
    self.connected = NO;
    [self updateUI];
}


- (void) FLIROneSDKTuningStateDidChange:(FLIROneSDKTuningState)newTuningState {
    self.tuningState = newTuningState;
}


- (UIImage *)imageForFrameAtTimestamp:(CMTime)timestamp{
    return [[UIImage alloc] init];
}


- (void) updateUI {
    dispatch_async(dispatch_get_main_queue(), ^{
        //here is where we set the visual image
        self.visualYCbCrImage = [self imageByDrawingCircleOnImage:self.visualYCbCrImage];
        [self.visualYCBView setImage:self.visualYCbCrImage];
        self.visualYCBView.transform = CGAffineTransformMakeRotation(M_PI_2); //rotate by 90 degrees to match orientation
        
        //set thermalView
        [self.thermalView setImage:self.radiometricImage];
        self.thermalView.transform = CGAffineTransformMakeRotation(M_PI_2); //rotate thermal 90 degrees
        
        //final version won't need this, this is for testing
        if (self.connected)
            self.connectionLabel.text = @"connected";
        else
            self.connectionLabel.text = @"disconnected";
        if (self.foreheadSet)
            self.detectLabel.text = @"forehead detected";
        
        
        if(self.thermalData && self.options & FLIROneSDKImageOptionsThermalRadiometricKelvinImage) {
            @synchronized(self) {
                [self performTemperatureCalculations];
            }
        }
        self.visualSizeLabel.text = [NSString stringWithFormat:@"visViewSize: %0.2f x %0.2f", self.visualYCBView.image.size.width, self.visualYCBView.image.size.height];
        //[NSString stringWithFormat:@"visImgSize: %0.2f x %0.2f",self.visualSize.width,self.visualSize.height];
        
        self.frameCountLabel.text = [NSString stringWithFormat:@"Count: %ld, %0.2f", (long)self.frameCount, self.fps];
        
        for (CIFaceFeature *faceFeature in self.faceFeatures){
            
            self.originLabel.text = [NSString stringWithFormat:@"face origin: %0.2f %0.2f", faceFeature.bounds.origin.x, faceFeature.bounds.origin.y];
            
            self.faceFeatureLabel.text = [NSString stringWithFormat:@"faceSize: %0.2f x %0.2f", faceFeature.bounds.size.height, faceFeature.bounds.size.width];
            
            self.rightEyeLabel.text = [NSString stringWithFormat:@"right eye: %0.2f %0.2f", faceFeature.rightEyePosition.x, faceFeature.rightEyePosition.y];
            
            
        
            self.foreheadLabel.text = [NSString stringWithFormat:@"forehead temp: %@", self.tempPoints[@"forehead"]];
            
            
            
            self.leftEyeLabel.text = [NSString stringWithFormat:@"left eye: %0.2f %0.2f", faceFeature.leftEyePosition.x, faceFeature.leftEyePosition.y];
            
            self.mouthLabel.text = [NSString stringWithFormat:@"mouth: %0.2f %0.2f", faceFeature.mouthPosition.x, faceFeature.mouthPosition.y];
            
//            //for now, draw a box around eyes and mouth for both thermal and visual
//            // Get the bounding rectangle of the face
//            CGRect bounds = faceFeature.bounds;
//            
//            [[UIColor colorWithWhite:1.0 alpha:1.0] set];
//            [UIBezierPath bezierPathWithRect:(bounds)];
//            
//            // Get the position of facial features
//            if (faceFeature.hasLeftEyePosition) {
//                CGPoint leftEyePosition = faceFeature.leftEyePosition;
//                
//                [[UIColor colorWithWhite:1.0 alpha:1.0] set];
//                [UIBezierPath bezierPathWithRect:(CGRectMake(leftEyePosition.x - 10.0, leftEyePosition.y - 10.0, 20.0, 20.0))];
//            }
//            
//            if (faceFeature.hasRightEyePosition) {
//                CGPoint rightEyePosition = faceFeature.rightEyePosition;
//                
//                [[UIColor colorWithWhite:1.0 alpha:1.0] set];
//                [UIBezierPath bezierPathWithRect:(CGRectMake(rightEyePosition.x - 10.0, rightEyePosition.y - 10.0, 20.0, 20.0))];
//            }
//            
//            if (faceFeature.hasMouthPosition) {
//                CGPoint mouthPosition = faceFeature.mouthPosition;
//                
//                [[UIColor colorWithWhite:1.0 alpha:1.0] set];
//                [UIBezierPath bezierPathWithRect:(CGRectMake(mouthPosition.x - 10.0, mouthPosition.y - 10.0, 20.0, 20.0))];
//            }

        }
        
        //reset faceFeatures
        self.faceFeatures = @[];
    });
}

// once per frame, this method is called and notifies the delegate. Depending on type of image, a different
// didReceive method gets called
- (void)FLIROneSDKDelegateManager:(FLIROneSDKDelegateManager *)delegateManager didReceiveFrameWithOptions:(FLIROneSDKImageOptions)options metadata:(FLIROneSDKImageMetadata *)metadata {
    self.options = options;
    if(!(self.options & FLIROneSDKImageOptionsVisualYCbCr888Image)) {
        self.visualYCbCrImage = nil;
    }
    if(!(self.options & FLIROneSDKImageOptionsThermalRadiometricKelvinImage)) {
        self.radiometricImage = nil;
    }
    
    self.frameCount += 1;
    NSTimeInterval now = [[NSDate date] timeIntervalSince1970];
    
    if(self.lastTime > 0) {
        self.fps = 1.0/(now - self.lastTime);
    }
    
    self.lastTime = now;
    
    [self updateUI];
}


// when visualYCbCr is captured, this gets called. Best formatted for temperature data. called by didReceiveFrameWithOptions
- (void)FLIROneSDKDelegateManager:(FLIROneSDKDelegateManager *)delegateManager didReceiveVisualYCbCr888Image:(NSData *)visualYCbCr888Image imageSize:(CGSize)size {
    
    @synchronized(self) {
        self.visualData = visualYCbCr888Image; //update visual data
        self.visualSize = size;
    }
    
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        //background thread
        self.faceFeatures = [self.facedetector featuresInImage:[[CIImage alloc] initWithImage: self.visualYCbCrImage] options:_imgOption];
        dispatch_async(dispatch_get_main_queue(), ^(void){
            //main thread
            self.visualYCbCrImage = [FLIROneSDKUIImage imageWithFormat:FLIROneSDKImageOptionsVisualYCbCr888Image andData:visualYCbCr888Image andSize:size];
//            NSLog(@"%ld", self.visualYCbCrImage.imageOrientation);
        });
        
    });
    
}

// when radiometric data is captured, this getes called. called by didReceiveFrameWithOptions
- (void)FLIROneSDKDelegateManager:(FLIROneSDKDelegateManager *)delegateManager didReceiveRadiometricData:(NSData *)radiometricData imageSize:(CGSize)size {
    
    @synchronized(self) {
        self.thermalData = radiometricData; //update thermal data here
        self.thermalSize = size;
    }
    
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_HIGH, 0), ^{
        self.radiometricImage = [FLIROneSDKUIImage imageWithFormat:FLIROneSDKImageOptionsThermalRadiometricKelvinImage andData:radiometricData andSize:size];
        
        [self updateUI];
    });
}



//Translates a coordinate from the visualYCbCr view to the radiometric view
//visual is higher resolution than thermal
- (CGFloat)resolutionTranslateX:(CGFloat)visX {
    CGFloat radX;
    
    CGFloat widthPercent = visX/self.visualSize.width;
    radX = widthPercent*self.thermalSize.width;
    
    return radX;
}

- (CGFloat)resolutionTranslateY:(CGFloat)visY {
    CGFloat radY;
    
    CGFloat heightPercent = visY/self.visualSize.height;
    radY = heightPercent*self.thermalSize.height;

    return radY;
}

// converts temperature data into degrees (Kelvin). NOTE the pixels in the image are row major, ex:
// [0] [1] [2] [3] [4]
// [5] [6] [7] [8] [9]
// [10] [11] ...
//
// sets tempPoints and foreheadCheekPositions
- (void) performTemperatureCalculations {
    //where the face features are located
    if (self.faceFeatures.count == 0)
        return;
    CIFaceFeature* faceFeature = self.faceFeatures[0];
    CGFloat faceWidth = faceFeature.bounds.size.width;
    CGFloat faceHeight = faceFeature.bounds.size.height;

    //
    // coordinates for forehead and cheeks
    //
    CGFloat foreTX = -69; //forehead x point
    CGFloat foreTY = -69; //forehead y
    CGPoint foreT;
    
    CGFloat rightTX = -69;
    CGFloat rightTY = -69;
    
    CGFloat leftTX = -69;
    CGFloat leftTY = -69;

    //can only calculate forehead location given righteye and lefteye
    BOOL hasForehead = faceFeature.hasRightEyePosition && faceFeature.hasLeftEyePosition;
    //right cheek needs right eye and mouth
    BOOL hasRightCheek = faceFeature.hasRightEyePosition && faceFeature.hasMouthPosition;
    //left cheek needs left eye and mouth
    BOOL hasLeftCheek = faceFeature.hasLeftEyePosition && faceFeature.hasMouthPosition;
    
    if(hasForehead) {
        //visual coordinates
        CGPoint foreV = CGPointMake((faceFeature.leftEyePosition.x + faceFeature.rightEyePosition.x)/2, ((faceFeature.bounds.origin.y) + fminf(faceFeature.rightEyePosition.y, faceFeature.leftEyePosition.y))/2);
        foreTX = [self resolutionTranslateX:foreV.x];
        foreTX = floorf(foreTX);
        foreTY = [self resolutionTranslateY:foreV.y];
        foreTY = floorf(foreTY);
        
//        foreT = [self.thermalView convertPoint:foreConvert fromView:self.visualYCBView];
//        CGFloat foreX = (faceFeature.leftEyePosition.x + faceFeature.rightEyePosition.x)/2;
//        CGFloat foreY = ((faceHeight+faceFeature.bounds.origin.y) + fmaxf(faceFeature.rightEyePosition.y, faceFeature.leftEyePosition.y))/2;
        
        self.foreXLabel.text = [NSString stringWithFormat:@"foreV: %0.2f, %0.2f", foreV.x, foreV.y];
        //thermal coordinates
//        foreTX = [self resolutionTranslateX:foreX];
        
        
        //foreT = [self.thermalView convertPoint:CGPointMake(foreX, foreY) fromView:self.visualYCBView];
        self.foreTXLabel.text = [NSString stringWithFormat:@"foreT: %0.2f, %0.2f", foreTX, foreTY];
        
        
//        foreTX = floorf(foreTX);
//        if(foreTX != -69) {
//            self.foreTXLabel.text = [NSString stringWithFormat:@"foreTX: %0.2f", foreTX];
//        }
//        foreTY = [self resolutionTranslateY:foreY];
//        foreTY = floorf(foreTY);
    }
    
    if(hasRightCheek) {
        //visual coordinates
        CGFloat rightX = faceFeature.rightEyePosition.x;
        CGFloat rightY = (faceFeature.rightEyePosition.y + faceFeature.mouthPosition.y)/2;
        
        //thermal coordinates
        rightTX = [self resolutionTranslateX:rightX];
        rightTY = [self resolutionTranslateY:rightY];
    }
    
    if(hasLeftCheek) {
        //visual coordinates
        CGFloat leftX = faceFeature.leftEyePosition.x;
        CGFloat leftY = (faceFeature.leftEyePosition.y + faceFeature.mouthPosition.y)/2;
        
        //thermal
        leftTX = [self resolutionTranslateX:leftX];
        leftTY = [self resolutionTranslateY:leftY];
        
    }
    
    //grab a two-byte pointer to the first value in the thermalData array, which is a pointer to pixel (0,0)
    uint16_t *tempData = (uint16_t*)[self.thermalData bytes];
    
    //get total number of pixels to iterate over
    int totalPixels = self.thermalSize.width * self.thermalSize.height;
    self.thermalSizeLabel.text = [NSString stringWithFormat:@"tViewSize: %0.2f x %0.2f", self.thermalView.image.size.width, self.thermalView.image.size.height];
    
    //[NSString stringWithFormat:@"tImgSize: %0.2f x %0.2f",self.thermalSize.width,self.thermalSize.height];
    
    float degreesKelvin; //gets temperature at index i
    CGFloat xCoord; //x coord of thermal data
    CGFloat yCoord; //y coord of thermal data
    
    //TODO: since we know where the points are, do we need to iterate over all pixels? I think we can get away
    //with just reading the 3 specific points 
    for(int i = 0; i < totalPixels; i++) {
        degreesKelvin = tempData[i] / 100.0;
        xCoord = (i % (int)self.thermalSize.width);
        xCoord = floorf(xCoord);
        yCoord = (i / self.thermalSize.height);
        yCoord = floorf(yCoord);
        
        //get temperature of forehead
        if(xCoord == foreTX && yCoord == foreTY){
            self.foreheadSet = YES;

            //store in dictionary
            self.tempPoints[@"forehead"] = [NSNumber numberWithFloat:degreesKelvin];
            
            //store (thermal) coordinates
            self.foreheadCheekPositions[@"forehead"] = [NSValue valueWithCGPoint:CGPointMake(xCoord,yCoord)];
        }
        
        if(xCoord == leftTX && yCoord == leftTY) {
            //store in dictionary
            self.tempPoints[@"left_cheek"] = [NSNumber numberWithFloat:degreesKelvin];
            
            //store (thermal) coordinates
            self.foreheadCheekPositions[@"left_cheek"] = [NSValue valueWithCGPoint:CGPointMake(xCoord,yCoord)];
        }
        
        if(xCoord == rightTX && yCoord == rightTY) {
            //store in dictionary
            self.tempPoints[@"right_cheek"] = [NSNumber numberWithFloat:degreesKelvin];
            
            //store (thermal) coordinates
            self.foreheadCheekPositions[@"right_cheek"] = [NSValue valueWithCGPoint:CGPointMake(xCoord,yCoord)];
        }
    }
}


- (UIImage *)imageByDrawingCircleOnImage:(UIImage *)image
{
    if (self.faceFeatures.count == 0)
        return image;
    
    
    CIFaceFeature* faceFeature = self.faceFeatures[0];
    
    float faceWidth = faceFeature.bounds.size.width;
    float faceHeight = faceFeature.bounds.size.height;
    
    // begin a graphics context of sufficient size
    UIGraphicsBeginImageContext(image.size);
    
    // draw original image into the context
    [image drawAtPoint:CGPointZero];
    
    // get the context for CoreGraphics
    CGContextRef ctx = UIGraphicsGetCurrentContext();
    
    // set stroking color and draw circle
    [[UIColor redColor] setStroke];
    
    
    
    
    if(faceFeature.hasLeftEyePosition){
        CGRect leftEyeRect =  CGRectMake(faceFeature.leftEyePosition.x-faceWidth*0.15, faceFeature.leftEyePosition.y-faceWidth*0.15, faceWidth*0.3, faceWidth*0.3);
        leftEyeRect = CGRectInset(leftEyeRect, 0, 0);
        CGContextStrokeRect(ctx, leftEyeRect);
    }
    
    if(faceFeature.hasRightEyePosition){
        CGRect rightEyeRect =  CGRectMake(faceFeature.rightEyePosition.x-faceWidth*0.15, faceFeature.rightEyePosition.y-faceWidth*0.15, faceWidth*0.3, faceWidth*0.3);
        rightEyeRect = CGRectInset(rightEyeRect, 0, 0);
        CGContextStrokeRect(ctx, rightEyeRect);
    }
    if (faceFeature.hasMouthPosition){
        CGRect mouthRect = CGRectMake(faceFeature.mouthPosition.x-faceWidth*0.2, faceFeature.mouthPosition.y-faceWidth*0.2, faceWidth*0.4, faceWidth*0.4);
        mouthRect = CGRectInset(mouthRect, 0, 0);
        CGContextStrokeRect(ctx, mouthRect);
    }
    
    
    
    // make circle rect 5 px from border
    CGRect facerect = CGRectMake(faceFeature.bounds.origin.x, faceFeature.bounds.origin.y,
                                   faceWidth,
                                   faceHeight);
    
    
    facerect = CGRectInset(facerect, 0, 0);
    
    // draw circle
    CGContextStrokeRect(ctx, facerect);
    
    // make image out of bitmap context
    UIImage *retImage = UIGraphicsGetImageFromCurrentImageContext();
    
    // free the context
    UIGraphicsEndImageContext();
    
    return retImage;
}



//grab any valid image delivered from the sled
- (UIImage *)currentImage {
    UIImage *image = self.visualYCbCrImage;
    if(!image) {
        image = self.radiometricImage;
    }
    if(!image) {
        image = self.visualYCbCrImage;
    }
    return image;
}

// only support landscape orientation
- (NSUInteger)supportedInterfaceOrientations
{
    return UIInterfaceOrientationMaskLandscapeLeft;
}

@end
