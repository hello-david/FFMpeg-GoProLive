//
//  GPAudioLive.m
//  GoProLive
//
//  Created by David.Dai on 16/8/16.
//  Copyright © 2016年 David.Dai. All rights reserved.
//

#import "GPAudioLive.h"
#import "AACEncoder.h"

@interface GPAudioLive() <AVCaptureAudioDataOutputSampleBufferDelegate>

@end

@implementation GPAudioLive
{
    AVCaptureSession        *_caputreSession;
    AVCaptureConnection     *_audioConnection;
    dispatch_queue_t        _audioQueue;
    AACEncoder              *_aacEncoder;
}

- (instancetype)init
{
    self = [super init];
    if (self) {
        _caputreSession = [[AVCaptureSession alloc]init];
        _aacEncoder = [[AACEncoder alloc]init];
        _audioQueue = dispatch_queue_create("com.GPAudioLive", DISPATCH_QUEUE_SERIAL);
        [self setupAudioCapture];
    }
    return self;
}

- (void)stratAACAudioFromMic
{
    [_caputreSession startRunning];
}

- (void)stopAACAudioFromMic
{
    [_caputreSession stopRunning];
}

- (void)setupAudioCapture
{
    NSError *error = nil;
    AVCaptureDevice *audioDevice = [AVCaptureDevice defaultDeviceWithMediaType:AVMediaTypeAudio];
    AVCaptureDeviceInput *audioInput = [[AVCaptureDeviceInput alloc]initWithDevice:audioDevice error:&error];
    
    if (error){
        NSLog(@"Error getting audio input device:%@",error.description);
    }
    
    if ([_caputreSession canAddInput:audioInput]) {
        [_caputreSession addInput:audioInput];
    }
    
    AVCaptureAudioDataOutput *audioOutput = [AVCaptureAudioDataOutput new];
    [audioOutput setSampleBufferDelegate:self queue:_audioQueue];
    if ([_caputreSession canAddOutput:audioOutput]) {
        [_caputreSession addOutput:audioOutput];
    }
    
    _audioConnection = [audioOutput connectionWithMediaType:AVMediaTypeAudio];
}

#pragma mark ---------------------Capture audio output delegate----------------------------------
- (void)captureOutput:(AVCaptureOutput *)captureOutput
didOutputSampleBuffer:(CMSampleBufferRef)sampleBuffer
       fromConnection:(AVCaptureConnection *)connection
{
    if(connection == _audioConnection){
        [_aacEncoder encodeSampleBuffer:sampleBuffer completionBlock:^(NSData *encodedData, NSError *error) {
            [[NSNotificationCenter defaultCenter] postNotificationName:@"aacAudio" object:encodedData];
        }];
    }
}
@end
