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


@end

