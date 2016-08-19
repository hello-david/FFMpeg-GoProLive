//
//  GPPreviewHack.m
//  GoProLive
//
//  Created by David.Dai on 16/8/2.
//  Copyright © 2016年 David.Dai. All rights reserved.
//

#import "GPPreviewHack.h"
#import "GCDAsyncUdpSocket.h"

@interface GPPreviewHack()<GCDAsyncUdpSocketDelegate>

@end

@implementation GPPreviewHack
{
    GCDAsyncUdpSocket       *_magicPacketSocket;
    NSTimer                 *_previewRequestTimer;
}

- (instancetype)init
{
    self = [super init];
    if (self) {
        NSError *error = nil;
        _magicPacketSocket = [[GCDAsyncUdpSocket alloc] initWithDelegate:self delegateQueue:dispatch_queue_create("com.magicPacket", DISPATCH_QUEUE_SERIAL)];
        if(![_magicPacketSocket bindToPort:0 error:&error]){
            NSLog(@"bind udp socket err");
        }
        if (![_magicPacketSocket beginReceiving:&error]) {
            NSLog(@"begin udp socket err");
        }
        
        [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(startKeepLive) name:kGoProHackKeepAlive object:nil];
        [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(stopHack) name:kGoProHackStopAlvie object:nil];
    }
    return self;
}

- (void)startHack
{
    [_magicPacketSocket sendData:[self magicPacket] toHost:@"10.5.5.9" port:9 withTimeout:1 tag:-1];
    [self resetPreview];
}

- (void)stopHack
{
    if(_previewRequestTimer)
    {
        [_previewRequestTimer invalidate];
        _previewRequestTimer = nil;
    }
}

- (void)startKeepLive
{
    if(_previewRequestTimer)
    {
        [_previewRequestTimer invalidate];
        _previewRequestTimer = nil;
    }
    _previewRequestTimer = [NSTimer scheduledTimerWithTimeInterval:8 target:self selector:@selector(resetPreview) userInfo:nil repeats:YES];
}

#pragma mark -----------------Midletreament-------------------
- (void)resetPreview
{
    dispatch_async(dispatch_get_main_queue(), ^{
        [_magicPacketSocket sendData:[self magicPacket] toHost:@"10.5.5.9" port:9 withTimeout:1 tag:-1];
        [self sendAliveRequest];
    });
}

- (NSData *)magicPacket
{
    //construct mac address
    unsigned char macAddrToSend[102];
    unsigned char mac[6];
    for(int i = 0; i < 6; i++)
        macAddrToSend[i] = 0xff;
    
    //current go pro bssid f6:dd:9e:11:81:db
    mac[0] = 0xf6;
    mac[1] = 0xdd;
    mac[2] = 0x9e;
    mac[3] = 0x11;
    mac[4] = 0x81;
    mac[5] = 0xdb;
    for(int i = 1; i <= 16; i++)
        memcpy(&macAddrToSend[i * 6], &mac, 6 * sizeof(unsigned char));
    
    NSData *data = [NSData dataWithBytes:macAddrToSend length:sizeof(macAddrToSend)];
    return data;
}

- (void)sendAliveRequest
{
    NSURLSessionConfiguration *config = [NSURLSessionConfiguration defaultSessionConfiguration];
    NSURLSession *netWorkSession = [NSURLSession sessionWithConfiguration:config];
    NSURLSessionDataTask *getLive = [netWorkSession dataTaskWithURL:[NSURL URLWithString:@"http://10.5.5.9/gp/gpControl/execute?p1=gpStream&a1=proto_v2&c1=restart"]];
    [getLive resume];
}

@end
