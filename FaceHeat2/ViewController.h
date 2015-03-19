//
//  ViewController.h
//  FaceHeatIOS
//
//  Created by Alick, Daijiro on 2/19/15.
//  Copyright (c) 2015 Team3. All rights reserved.
//

#import <UIKit/UIKit.h>
#import <AVFoundation/AVFoundation.h>

#import <FLIROneSDK/FLIROneSDK.h>
#import <tgmath.h>

//for bluetooth
#import <ImageIO/ImageIO.h>
#import <CoreImage/CoreImage.h>
#import <QuartzCore/QuartzCore.h>
#import <CoreBluetooth/CoreBluetooth.h>
#import "BLE.h"


@interface ViewController : UIViewController <FLIROneSDKImageReceiverDelegate, FLIROneSDKStreamManagerDelegate, FLIROneSDKVideoRendererDelegate, FLIROneSDKImageEditorDelegate>


@property (weak, nonatomic) IBOutlet UILabel *faceFeatureLabel;

@property (weak, nonatomic) IBOutlet UILabel *rightEyeLabel;
@property (weak, nonatomic) IBOutlet UILabel *leftEyeLabel;
@property (weak, nonatomic) IBOutlet UILabel *mouthLabel;
@property (weak, nonatomic) IBOutlet UILabel *originLabel;
@property (weak, nonatomic) IBOutlet UILabel *frameCountLabel;
@property (weak, nonatomic) IBOutlet UILabel *connectionLabel;

@property (weak, nonatomic) IBOutlet UILabel *foreheadLabel;
@property (weak, nonatomic) IBOutlet UILabel *detectLabel;
@property (weak, nonatomic) IBOutlet UILabel *foreTXLabel;
@property (weak, nonatomic) IBOutlet UILabel *foreXLabel;
@property (weak, nonatomic) IBOutlet UILabel *thermalSizeLabel;
@property (weak, nonatomic) IBOutlet UILabel *visualSizeLabel;

@property(nonatomic, strong) BLE *ble;
@property(nonatomic, strong) CBPeripheral *activePeripheral;
@property(nonatomic, strong) AVCaptureVideoDataOutput *output;
@property (nonatomic, strong) AVCaptureVideoPreviewLayer *previewLayer;
- (IBAction)scan:(id)sender;
@property (weak, nonatomic) IBOutlet UILabel *currentAngleLabel;
@property (weak, nonatomic) IBOutlet UILabel *currentTiltLabel;

@end

