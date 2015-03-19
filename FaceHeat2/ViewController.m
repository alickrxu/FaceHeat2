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

@property (nonatomic) BOOL faceHeatDetected;



@end

@implementation ViewController
@synthesize ble;
int currentAngle = 125; //current horizontal angle of the rig
int horizontalRigBounds = 20; //boundaries of the looking box for the rig to move. in context of thermal camera
int verticalRigBounds = 100;


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
    
    self.imgOption = @{};//@{CIDetectorImageOrientation: @3}; //kCBImagePropertyOrientation
    
    NSDictionary *detectoroptions = @{ CIDetectorAccuracy : CIDetectorAccuracyHigh, CIDetectorTracking: @YES};
    self.facedetector = [CIDetector detectorOfType:CIDetectorTypeFace context:nil options:detectoroptions];
    
    // add view controller to FLIR stream manager delegates
    [[FLIROneSDKStreamManager sharedInstance] addDelegate:self];
    [[FLIROneSDKStreamManager sharedInstance] setImageOptions: self.options];
    self.faceFeatures = @[];
    
    //initialize dictionaries
    self.tempPoints = [NSMutableDictionary dictionary];
    self.tempPoints[@"left_cheek"] = @69;
    self.tempPoints[@"forehead"] = @69;
    self.tempPoints[@"right_cheek"] = @69;
    self.foreheadCheekPositions = [NSMutableDictionary dictionary];
    
    self.foreheadSet = NO;
    self.faceHeatDetected = NO;
    //disable locking of the screen
    [[UIApplication sharedApplication] setIdleTimerDisabled:YES];
    
    //UIImage *img = [UIImage imageNamed:@"face-map.jpg"];
    //self.faceFeatures = [self.facedetector featuresInImage:[[CIImage alloc] initWithImage:img] options:@{}];
    //self.visualYCBView.image = img;
    // self.thermalView.image = [self imageByDrawingCircleOnImage:img];
    
    //setup bluetooth
    ble = [[BLE alloc] init];
    [ble controlSetup];
    ble.delegate = self;
    
}


- (void)didReceiveMemoryWarning {
    [super didReceiveMemoryWarning];
    // Dispose of any resources that can be recreated.
}


- (void) FLIROneSDKDidConnect {
    self.connected = YES;
    [self scanForPeripherals];

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
        //rotate by 90 degrees to match landscape orientation
//        self.visualYCBView.transform = CGAffineTransformMakeRotation(M_PI_2);
        
        //set thermalView
        [self.thermalView setImage:self.radiometricImage];
//        self.thermalView.transform = CGAffineTransformMakeRotation(M_PI_2); //rotate thermal 90 degrees
        
        //final version won't need this, this is for testing
        if (self.connected)
            self.connectionLabel.text = @"connected";
        else
            self.connectionLabel.text = @"disconnected";
        if (self.faceHeatDetected)
            self.detectLabel.text = @"face detected!!";
        else
            self.detectLabel.text = @"no face yet";
        
        self.currentAngleLabel.text = [NSString stringWithFormat:@"currentAngle: %d", currentAngle];
        
        
        if(self.thermalData && self.options & FLIROneSDKImageOptionsThermalRadiometricKelvinImage) {
            @synchronized(self) {
                [self performTemperatureCalculations];
            }
        }
        self.visualSizeLabel.text = [NSString stringWithFormat:@"cheek temps: %@ , %@", self.tempPoints[@"left_cheek"], self.tempPoints[@"right_cheek"]];
        //[NSString stringWithFormat:@"visImgSize: %0.2f x %0.2f",self.visualSize.width,self.visualSize.height];
        
        self.frameCountLabel.text = [NSString stringWithFormat:@"Count: %ld, %0.2f", (long)self.frameCount, self.fps];
        
        for (CIFaceFeature *faceFeature in self.faceFeatures){
            
//            self.originLabel.text = [NSString stringWithFormat:@"face origin: %0.2f %0.2f", faceFeature.bounds.origin.x, faceFeature.bounds.origin.y];
            
            self.faceFeatureLabel.text = [NSString stringWithFormat:@"faceSize: %0.2f x %0.2f", faceFeature.bounds.size.height, faceFeature.bounds.size.width];
            
//            self.rightEyeLabel.text = [NSString stringWithFormat:@"right eye: %0.2f %0.2f", faceFeature.rightEyePosition.x, faceFeature.rightEyePosition.y];
            
            
        
//            self.foreheadLabel.text = [NSString stringWithFormat:@"forehead temp: %@", self.tempPoints[@"forehead"]];
            
            
            
//            self.leftEyeLabel.text = [NSString stringWithFormat:@"left eye: %0.2f %0.2f", faceFeature.leftEyePosition.x, faceFeature.leftEyePosition.y];
            
//            self.mouthLabel.text = [NSString stringWithFormat:@"mouth: %0.2f %0.2f", faceFeature.mouthPosition.x, faceFeature.mouthPosition.y];
            
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

/*
 *  FACE DETECTION
 *
 *
 */

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
        self.faceFeatures = [self.facedetector featuresInImage:[[CIImage  alloc] initWithImage:self.visualYCbCrImage] options:self.imgOption];
        
        dispatch_async(dispatch_get_main_queue(), ^(void){
            //main thread
            self.visualYCbCrImage = [FLIROneSDKUIImage imageWithFormat:FLIROneSDKImageOptionsVisualYCbCr888Image andData:visualYCbCr888Image andSize:size];
            self.visualYCbCrImage.imageOrientation;
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
// 1st of 3 metrics:
// 1: get temperature from forehead and cheeks. compare temperatures from forehead and cheeks - if they differ, then we have a face. Needs eyeposition
- (void) performTemperatureCalculations {
    
    CGAffineTransform transform = CGAffineTransformMakeScale(1, -1);
    CGAffineTransform transformToUIKit = CGAffineTransformTranslate(transform, 0, -self.visualYCbCrImage.size.height);

    //where the face features are located
    if (self.faceFeatures.count == 0)
        return;
    CIFaceFeature* faceFeature = self.faceFeatures[0];
    CGFloat faceWidth = faceFeature.bounds.size.width;
    CGFloat faceHeight = faceFeature.bounds.size.height;
    
    CGFloat faceThermalWidth = faceWidth/self.visualSize.width * self.thermalSize.width;
    CGFloat faceThermalHeight = faceHeight/self.visualSize.height * self.thermalSize.height;

    // coordinates for forehead and cheeks
    CGFloat foreTX = -69; //forehead x point
    CGFloat foreTY = -69; //forehead y
    
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
    
    //first transform the visual coordinates
    CGPoint leftEye = CGPointApplyAffineTransform(faceFeature.leftEyePosition, transformToUIKit);
    CGPoint rightEye = CGPointApplyAffineTransform(faceFeature.rightEyePosition, transformToUIKit);
    CGPoint mouth = CGPointApplyAffineTransform(faceFeature.mouthPosition, transformToUIKit);
    CGPoint origin = CGPointApplyAffineTransform(faceFeature.bounds.origin, transformToUIKit);
    
    self.originLabel.text = [NSString stringWithFormat:@"face origin: %0.2f %0.2f", origin.x, origin.y];

    //store all of the temperature points in the rectangles, used to get average temperature
    CGRect foreheadRect;
    CGRect leftCheekRect;
    CGRect rightCheekRect;
    NSMutableArray *foreheadTemps = [NSMutableArray array];
    NSMutableArray *rightCheekTemps = [NSMutableArray array];
    NSMutableArray *leftCheekTemps = [NSMutableArray array];

    
    if(hasForehead) {
        //visual coordinates
        CGPoint foreV = CGPointMake((leftEye.x + leftEye.x)/2, ((origin.y) - faceFeature.bounds.size.height + fminf(rightEye.y, leftEye.y))/2);
        foreTX = [self resolutionTranslateX:foreV.x];
        foreTX = floorf(foreTX);
        foreTY = [self resolutionTranslateY:foreV.y];
        foreTY = floorf(foreTY);
        
        //read a box of points and get the average of the temperatures
        foreheadRect = CGRectStandardize(CGRectMake(foreTX - faceThermalWidth*0.1, foreTY - faceThermalWidth*0.1, faceThermalWidth*0.2, faceThermalWidth*0.2));

        
        self.foreXLabel.text = [NSString stringWithFormat:@"foreV: %0.2f, %0.2f", foreV.x, foreV.y];
        self.foreTXLabel.text = [NSString stringWithFormat:@"foreT: %0.2f, %0.2f", foreTX, foreTY];
    }
    
    if(hasLeftCheek) {
        //visual coordinates
        CGFloat leftX = leftEye.x - 25;
        CGFloat leftY = (leftEye.y + mouth.y)/2;
        
        //thermal
        leftTX = floor([self resolutionTranslateX:leftX]);
        leftTY = floor([self resolutionTranslateY:leftY]);
        
        leftCheekRect = CGRectStandardize(CGRectMake(leftTX - faceThermalWidth*0.1, leftTY - faceThermalHeight*0.1, faceThermalWidth*0.1, faceThermalHeight*0.2));
        
        self.leftEyeLabel.text = [NSString stringWithFormat:@"leftTeye: %0.2f, %0.2f", leftTX, leftTY];
    }
    
    if(hasRightCheek) {
        //visual coordinates
        CGFloat rightX = rightEye.x + 25;
        CGFloat rightY = (rightEye.y + mouth.y)/2;
        
        //thermal coordinates
        rightTX = floor([self resolutionTranslateX:rightX]);
        rightTY = floor([self resolutionTranslateY:rightY]);
        
        rightCheekRect = CGRectStandardize(CGRectMake(rightTX, rightTY - faceThermalHeight*0.1, faceThermalWidth*0.1, faceThermalHeight*0.2));
        
        self.rightEyeLabel.text = [NSString stringWithFormat:@"rightTeye: %0.2f, %0.2f", rightTX, rightTY];
    }
    
    
    
    CGFloat mouthTX = floor([self resolutionTranslateX:mouth.x]);
    CGFloat mouthTY = floor([self resolutionTranslateY:mouth.y]);
    self.mouthLabel.text = [NSString stringWithFormat:@"mouthT: %0.2f, %0.2f", mouthTX, mouthTY];
    
    
    //grab a two-byte pointer to the first value in the thermalData array, which is a pointer to pixel (0,0)
    uint16_t *tempData = (uint16_t*)[self.thermalData bytes];
    
    //get total number of pixels to iterate over
    int totalPixels = self.thermalSize.width * self.thermalSize.height;
    self.thermalSizeLabel.text = [NSString stringWithFormat:@"tViewSize: %0.2f x %0.2f", self.thermalView.image.size.width, self.thermalView.image.size.height];
    
    //[NSString stringWithFormat:@"tImgSize: %0.2f x %0.2f",self.thermalSize.width,self.thermalSize.height];
    
    float degreesKelvin; //gets temperature at index i
    CGFloat xCoord; //x coord of thermal data
    CGFloat yCoord; //y coord of thermal data
    

    

    for(int i = 0; i < totalPixels; i++) {
        degreesKelvin = tempData[i] / 100.0;
        xCoord = (i % (int)self.thermalSize.width);
        xCoord = floorf(xCoord);
        yCoord = (i / self.thermalSize.height);
        yCoord = floorf(yCoord);
        
        //get temperature of forehead, check if wihtin foreheadrectangle bounds
        if((int)xCoord >= (int)CGRectGetMinX(foreheadRect)
           && (int)xCoord <= (int)CGRectGetMaxX(foreheadRect)
           && (int)yCoord >= (int)CGRectGetMinY(foreheadRect)
           && (int)yCoord <= (int)CGRectGetMaxY(foreheadRect)){
            [foreheadTemps addObject:[NSNumber numberWithFloat:degreesKelvin]];
        }
        
        //get temperature of leftcheek
        if((int)xCoord >= (int)CGRectGetMinX(leftCheekRect)
           && (int)xCoord <= (int)CGRectGetMaxX(leftCheekRect)
           && (int)yCoord >= (int)CGRectGetMinY(leftCheekRect)
           && (int)yCoord <= (int)CGRectGetMaxY(leftCheekRect)) {
            [leftCheekTemps addObject:[NSNumber numberWithFloat:degreesKelvin]];
        }
        
        //get temperature of rightcheek
        if((int)xCoord >= (int)CGRectGetMinX(rightCheekRect)
           && (int)xCoord <= (int)CGRectGetMaxX(rightCheekRect)
           && (int)yCoord >= (int)CGRectGetMinY(rightCheekRect)
           && (int)yCoord <= (int)CGRectGetMaxY(rightCheekRect)) {
            [rightCheekTemps addObject:[NSNumber numberWithFloat:degreesKelvin]];
        }
    }
    
    //after getting all the temperature values, calculate average temperature
    
    int i;
    float foreheadTotal;
    float leftCheekTotal;
    float rightCheekTotal;
    
    //forehead average temperature
    for(i = 0; i < [foreheadTemps count]; i++) {
        foreheadTotal += [foreheadTemps[i] floatValue];
    }
    foreheadTotal = foreheadTotal/[foreheadTemps count]; //average
    //store in dictionary
    self.tempPoints[@"forehead"] = [NSNumber numberWithFloat:foreheadTotal];
    //store coordinates of the origin
    self.foreheadCheekPositions[@"forehead"] = [NSValue valueWithCGPoint:CGPointMake(foreheadRect.origin.x,foreheadRect.origin.y)];
    
    //left cheek average temperature
    for(i = 0; i < [leftCheekTemps count]; i++) {
        leftCheekTotal += [leftCheekTemps[i] floatValue];
    }
    leftCheekTotal = leftCheekTotal/[leftCheekTemps count];
    self.tempPoints[@"left_cheek"] = [NSNumber numberWithFloat:leftCheekTotal];
    self.foreheadCheekPositions[@"left_cheek"] = [NSValue valueWithCGPoint:CGPointMake(leftCheekRect.origin.x,leftCheekRect.origin.y)];
    
    //right cheek average temperature
    for(i = 0; i < [rightCheekTemps count]; i++) {
        rightCheekTotal += [rightCheekTemps[i] floatValue];
    }
    rightCheekTotal = rightCheekTotal/[rightCheekTemps count];
    self.tempPoints[@"right_cheek"] = [NSNumber numberWithFloat:rightCheekTotal];
    self.foreheadCheekPositions[@"right_cheek"] = [NSValue valueWithCGPoint:CGPointMake(rightCheekRect.origin.x, rightCheekRect.origin.y)];
    
    //FACE DETECTION
    //if forehead is greater than the left and right cheeks by at least two degrees
    if(foreheadTotal - (leftCheekTotal + rightCheekTotal)/2 >= 2) {
        self.faceHeatDetected = YES;
        // MOVE THE RIG
        //horizontal movement: track the forehead x
        CGFloat midForehead = CGRectGetMidX(foreheadRect);
        
        if(midForehead > horizontalRigBounds && midForehead < self.visualSize.width - horizontalRigBounds) {
            if(midForehead > self.thermalSize.width/2) {
                currentAngle += 5;
            }
            else if(midForehead < self.thermalSize.width/2) {
                currentAngle -= 5;
            }
            if (currentAngle > 255)
                currentAngle = 255;
            else if (currentAngle < 0)
                currentAngle = 0;
        }
        [self moveRigLeftOrRight:currentAngle];
    }
    else {
        self.faceHeatDetected = NO;
    }

}

// utility routing used during image capture to set up capture orientation
- (AVCaptureVideoOrientation)avOrientationForDeviceOrientation:(UIDeviceOrientation)deviceOrientation
{
    AVCaptureVideoOrientation result = deviceOrientation;
    if ( deviceOrientation == UIDeviceOrientationLandscapeLeft )
        result = AVCaptureVideoOrientationLandscapeRight;
    else if ( deviceOrientation == UIDeviceOrientationLandscapeRight )
        result = AVCaptureVideoOrientationLandscapeLeft;
    return result;
}


- (UIImage *)imageByDrawingCircleOnImage:(UIImage *)image
{
//    UIDeviceOrientation curDeviceOrientation = [[UIDevice currentDevice] orientation];
//    AVCaptureVideoOrientation avcaptureOrientation = [self avOrientationForDeviceOrientation:curDeviceOrientation];

    //transform the points to the correct coordinates
    CGAffineTransform transform = CGAffineTransformMakeScale(1, -1);
    CGAffineTransform transformToUIKit = CGAffineTransformTranslate(transform, 0, -image.size.height);

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
    
    CGPoint origin = CGPointApplyAffineTransform(faceFeature.bounds.origin, transformToUIKit);

    
    if(faceFeature.hasLeftEyePosition){
        // set stroking color and draw circle
        [[UIColor redColor] setStroke];
        CGPoint p = CGPointApplyAffineTransform(faceFeature.leftEyePosition, transformToUIKit);
        CGRect leftEyeRect =  CGRectMake(p.x-faceWidth*0.1, p.y-faceWidth*0.1, faceWidth*0.2, faceWidth*0.2);
        leftEyeRect = CGRectInset(leftEyeRect, 0, 0);
        CGContextStrokeRect(ctx, leftEyeRect);
    }
    
    if(faceFeature.hasRightEyePosition){
        // set stroking color and draw circle
        [[UIColor blueColor] setStroke];
        CGPoint p = CGPointApplyAffineTransform(faceFeature.rightEyePosition, transformToUIKit);
        CGRect rightEyeRect =  CGRectMake(p.x-faceWidth*0.1, p.y-faceWidth*0.1, faceWidth*0.2, faceWidth*0.2);
        rightEyeRect = CGRectInset(rightEyeRect, 0, 0);
        CGContextStrokeRect(ctx, rightEyeRect);
    }
    if (faceFeature.hasMouthPosition){
        // set stroking color and draw circle
        [[UIColor greenColor] setStroke];
        CGPoint p = CGPointApplyAffineTransform(faceFeature.mouthPosition, transformToUIKit);
        
        CGRect mouthRect = CGRectMake(p.x-faceWidth*0.2, p.y-faceWidth*0.2, faceWidth*0.4, faceWidth*0.4);
        
        mouthRect = CGRectInset(mouthRect, 0, 0);
        CGContextStrokeRect(ctx, mouthRect);
    }
    //forehead
    if(faceFeature.hasLeftEyePosition && faceFeature.hasRightEyePosition) {
        CGPoint leftEye = CGPointApplyAffineTransform(faceFeature.leftEyePosition, transformToUIKit);
        CGPoint rightEye = CGPointApplyAffineTransform(faceFeature.rightEyePosition, transformToUIKit);

        CGPoint foreV = CGPointMake((leftEye.x + rightEye.x)/2, (origin.y - faceFeature.bounds.size.height + fminf(rightEye.y, leftEye.y))/2);
        [[UIColor orangeColor] setStroke];
        CGRect foreheadRect =  CGRectMake(foreV.x-faceWidth*0.1, foreV.y-faceWidth*0.1, faceWidth*0.2, faceWidth*0.2);
        foreheadRect = CGRectInset(foreheadRect, 0, 0);
        CGContextStrokeRect(ctx, foreheadRect);
    }
    //left cheek
    if(faceFeature.hasLeftEyePosition && faceFeature.hasMouthPosition) {
        CGPoint leftEye = CGPointApplyAffineTransform(faceFeature.leftEyePosition, transformToUIKit);
        CGPoint mouth = CGPointApplyAffineTransform(faceFeature.mouthPosition, transformToUIKit);
        
        CGPoint cheekV = CGPointMake(leftEye.x - 25, (leftEye.y + mouth.y)/2);
        [[UIColor whiteColor] setStroke];
        CGRect leftCheekRect =  CGRectMake(cheekV.x-faceWidth*0.1, cheekV.y-faceHeight*0.1, faceWidth*0.1, faceHeight*0.2);
        leftCheekRect = CGRectInset(leftCheekRect, 0, 0);
        CGContextStrokeRect(ctx, leftCheekRect);

    }
    //right cheek
    if(faceFeature.hasRightEyePosition && faceFeature.hasMouthPosition) {
        CGPoint rightEye = CGPointApplyAffineTransform(faceFeature.rightEyePosition, transformToUIKit);
        CGPoint mouth = CGPointApplyAffineTransform(faceFeature.mouthPosition, transformToUIKit);
        
        CGPoint cheekV = CGPointMake(rightEye.x + 25, (rightEye.y + mouth.y)/2);
        [[UIColor cyanColor] setStroke];
        CGRect rightCheekRect =  CGRectMake(cheekV.x, cheekV.y-faceHeight*0.1, faceWidth*0.1, faceHeight*0.2);
        rightCheekRect = CGRectInset(rightCheekRect, 0, 0);
        CGContextStrokeRect(ctx, rightCheekRect);
    }

    
    
    // make circle rect 5 px from border
    CGRect facerect = CGRectMake(faceFeature.bounds.origin.x, faceFeature.bounds.origin.y,
                                   faceWidth,
                                   faceHeight);
    
    facerect = CGRectApplyAffineTransform(facerect, transformToUIKit);
    
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

/*
 *  BLUETOOTH
 *
 */
-(void) bleDidConnect {
//    AVCaptureSession *session = [[AVCaptureSession alloc] init];
//    session.sessionPreset = AVCaptureSessionPresetPhoto;
//    
//    //Add device
//    AVCaptureDevice *device =
//    [AVCaptureDevice defaultDeviceWithMediaType:AVMediaTypeVideo];
//    
//    //Input
//    AVCaptureDeviceInput *input = [AVCaptureDeviceInput deviceInputWithDevice:device error:nil];
//    
//    if (!input)
//    {
//        NSLog(@"No Input");
//    }
//    
//    [session addInput:input];
//    //Output
//    self.output = [[AVCaptureVideoDataOutput alloc] init];
//    [session addOutput:self.output];
//    self.output.videoSettings = @{ (NSString *)kCVPixelBufferPixelFormatTypeKey : @(kCVPixelFormatType_32BGRA) };
//    
//    
//    dispatch_queue_t queue = dispatch_queue_create("myQueue", NULL);
//    [_output setSampleBufferDelegate:self queue:queue];
//    
//    //Preview Layer
//    _previewLayer = [[AVCaptureVideoPreviewLayer alloc] initWithSession:session];
//    UIView *myView = self.view;
//    _previewLayer.frame = CGRectMake(0, 0, myView.bounds.size.height, myView.bounds.size.width);
//    _previewLayer.videoGravity = AVLayerVideoGravityResizeAspectFill;
//    [self.view.layer addSublayer:_previewLayer];
//    AVCaptureConnection *previewLayerConnection=self.previewLayer.connection;
//    previewLayerConnection.videoOrientation = AVCaptureVideoOrientationLandscapeLeft;
    char init1[] = {'S', 0x02, 0x04};
    [self sendData: [NSData dataWithBytes:init1 length:3]];
//    char centerX[] = {'O', 0x02, currentAngle};
//    
//    [self sendData:[NSData dataWithBytes:centerX length:3]];
//    //Start capture session
//    [session startRunning];
//    
}

- (void) sendData:(char *) bytes length:(int) length{
    [self sendData:[NSData dataWithBytes:bytes length:length]];
}

- (void) sendData:(NSData *) data {
    [ble write:data];
}

- (IBAction)scan:(id)sender {
    [self scanForPeripherals];
}

- (void) scanForPeripherals {
    [ble findBLEPeripherals:5];
    [NSTimer scheduledTimerWithTimeInterval:(float)5.0 target:self selector:@selector(connectionTimer:) userInfo:nil repeats:NO];
}

- (void) bleDidReceiveData:(unsigned char *)data length:(int)length{
    
    //   NSLog(@"received data: %s", data);
}

-(void) connectionTimer:(NSTimer *)timer
{
    if (ble.peripherals.count < 1){
        NSLog(@"none found");
        return;
    }
    self.activePeripheral = ble.peripherals[0];
    [ble connectPeripheral:self.activePeripheral];
}

//0x03 means move rig vertically
//0x02 means move rig horizontally
-(void) moveRigUpOrDown:(int)angle {
    if (angle > 255)
        angle = 255;
    else if (angle < 0)
        angle = 0;

    char data[] = {'O', 0x03, angle};
    [self sendData:[NSData dataWithBytes:data length:3]];
}

-(void) moveRigLeftOrRight:(int)angle {
    if (angle > 255)
        angle = 255;
    else if (angle < 0)
        angle = 0;
    
    char data[] = {'O', 0x02, angle};
    [self sendData:[NSData dataWithBytes:data length:3]];
}


//// only support landscape orientation
//- (NSUInteger)supportedInterfaceOrientations
//{
//    return UIInterfaceOrientationMaskPortrait;
//}

@end
