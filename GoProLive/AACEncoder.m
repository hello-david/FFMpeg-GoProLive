//
//  AACEncoder.m
//  GoProLive
//
//  Created by David.Dai on 16/8/16.
//  Copyright © 2016年 David.Dai. All rights reserved.
//

#import "AACEncoder.h"

@implementation AACEncoder
{
    dispatch_queue_t    _encodeQueue;
    dispatch_queue_t    _callbackQueue;
    AudioConverterRef   _audioConverter;
    char            *_aacBuffer;
    int             _aacBufferSize;
    char            *_pcmBuffer;
    size_t          _pcmBufferSize;
}

- (instancetype)init
{
    if(self = [super init])
    {
        _encodeQueue = dispatch_queue_create("com.GPAACEncode", NULL);
        _callbackQueue = dispatch_queue_create("com.GPAACEncodeCallBack", NULL);
        _audioConverter = NULL;
        _pcmBuffer = NULL;
        _pcmBufferSize = 0;
        _aacBufferSize = 1024;
        _aacBuffer = malloc(_aacBufferSize * sizeof(char));
        memset(_aacBuffer, 0, _aacBufferSize);
    }
    return self;
}

- (void) encodeSampleBuffer:(CMSampleBufferRef)sampleBuffer completionBlock:(void (^)(NSData * encodedData, NSError* error))completionBlock
{
    CFRetain(sampleBuffer);
    dispatch_async(_encodeQueue, ^
    {
        if (!_audioConverter)
            [self setupConverterFromBuffer:sampleBuffer];
        
        CMBlockBufferRef blockBuffer = CMSampleBufferGetDataBuffer(sampleBuffer);
        CFRetain(blockBuffer);
        OSStatus status = CMBlockBufferGetDataPointer(blockBuffer, 0, NULL, &_pcmBufferSize, &_pcmBuffer);
        NSError *error = nil;
        if (status != kCMBlockBufferNoErr){
            error = [NSError errorWithDomain:NSOSStatusErrorDomain code:status userInfo:nil];
        }
        
        memset(_aacBuffer, 0, _aacBufferSize);
        AudioBufferList outAudioBufferList = {0};
        outAudioBufferList.mNumberBuffers = 1;
        outAudioBufferList.mBuffers[0].mNumberChannels = 1;
        outAudioBufferList.mBuffers[0].mDataByteSize = _aacBufferSize;
        outAudioBufferList.mBuffers[0].mData = _aacBuffer;
        AudioStreamPacketDescription *outPacketDescription = NULL;
        UInt32 ioOutputDataPacketSize = 1;
        
        status = AudioConverterFillComplexBuffer(_audioConverter, inInputDataProc, (__bridge void *)(self), &ioOutputDataPacketSize, &outAudioBufferList, outPacketDescription);
        if(status != noErr){
             error = [NSError errorWithDomain:NSOSStatusErrorDomain code:status userInfo:nil];
        }
        
        NSData *data = nil;
        if (status == 0)
        {
            NSData *rawAAC = [NSData dataWithBytes:outAudioBufferList.mBuffers[0].mData length:outAudioBufferList.mBuffers[0].mDataByteSize];
            NSData *adtsHeader = [self adtsDataForPacketLength:rawAAC.length];
            NSMutableData *fullData = [NSMutableData dataWithData:adtsHeader];
            [fullData appendData:rawAAC];
            data = fullData;
        }
        
        else
            error = [NSError errorWithDomain:NSOSStatusErrorDomain code:status userInfo:nil];
        
        if (completionBlock)
        {
            dispatch_async(_callbackQueue, ^{
                completionBlock(data, error);
            });
        }
        CFRelease(sampleBuffer);
        CFRelease(blockBuffer);
    });
}

- (void)setupConverterFromBuffer:(CMSampleBufferRef)sampleBuffer
{
    AudioStreamBasicDescription inAudioStreamBasicDescription = *CMAudioFormatDescriptionGetStreamBasicDescription((CMAudioFormatDescriptionRef)CMSampleBufferGetFormatDescription(sampleBuffer));
    
    AudioStreamBasicDescription outAudioStreamBasicDescription = {0};
    outAudioStreamBasicDescription.mSampleRate          = inAudioStreamBasicDescription.mSampleRate;
    outAudioStreamBasicDescription.mFormatID            = kAudioFormatMPEG4AAC;
    outAudioStreamBasicDescription.mFormatFlags         = kMPEG4Object_AAC_LC;
    outAudioStreamBasicDescription.mBytesPerPacket      = 0;
    outAudioStreamBasicDescription.mFramesPerPacket     = 1024;
    outAudioStreamBasicDescription.mBytesPerFrame       = 0;
    outAudioStreamBasicDescription.mChannelsPerFrame    = 1;
    outAudioStreamBasicDescription.mBitsPerChannel      = 0;
    outAudioStreamBasicDescription.mReserved            = 0;
    AudioClassDescription *description = [self getAudioClassDescriptionWithType:kAudioFormatMPEG4AAC fromManufacturer:kAppleSoftwareAudioCodecManufacturer];
    
    OSStatus status = AudioConverterNewSpecific(&inAudioStreamBasicDescription, &outAudioStreamBasicDescription, 1, description, &_audioConverter);
    if (status != 0) {
        NSLog(@"setup converter: %d", (int)status);
    }
}

- (AudioClassDescription *)getAudioClassDescriptionWithType:(UInt32)type fromManufacturer:(UInt32)manufacturer
{
    static AudioClassDescription desc;
    UInt32 encoderSpecifier = type;
    OSStatus status;
    UInt32 size;
    status = AudioFormatGetPropertyInfo(kAudioFormatProperty_Encoders,sizeof(encoderSpecifier),&encoderSpecifier,&size);
    if (status) {
        NSLog(@"error getting audio format propery info: %d", (int)(status));
        return nil;
    }
    
    unsigned int count = size / sizeof(AudioClassDescription);
    AudioClassDescription descriptions[count];
    status = AudioFormatGetProperty(kAudioFormatProperty_Encoders, sizeof(encoderSpecifier),&encoderSpecifier,&size,descriptions);
    if (status) {
        NSLog(@"error getting audio format propery: %d", (int)(status));
        return nil;
    }
    
    for (unsigned int i = 0; i < count; i++)
    {
        if ((type == descriptions[i].mSubType) &&(manufacturer == descriptions[i].mManufacturer))
        {
            memcpy(&desc, &(descriptions[i]), sizeof(desc));
            return &desc;
        }
    }
    return nil;
}

#pragma mark ------------------------------------PCM input data pre setting----------------------------
static OSStatus inInputDataProc(AudioConverterRef inAudioConverter, UInt32 *ioNumberDataPackets, AudioBufferList *ioData, AudioStreamPacketDescription **outDataPacketDescription, void *inUserData)
{
    AACEncoder *encoder = (__bridge AACEncoder *)(inUserData);
    UInt32 requestedPackets = *ioNumberDataPackets;
    size_t copiedSamples = [encoder copyPCMSamplesIntoBuffer:ioData];
    if (copiedSamples < requestedPackets)
    {
        NSLog(@"PCM buffer isn't full enough!");
        *ioNumberDataPackets = 0;
        return -1;
    }
    *ioNumberDataPackets = 1;
    return noErr;
}

- (size_t) copyPCMSamplesIntoBuffer:(AudioBufferList*)ioData
{
    size_t originalBufferSize = _pcmBufferSize;
    if (!originalBufferSize) {
        return 0;
    }
    ioData->mBuffers[0].mData = _pcmBuffer;
    ioData->mBuffers[0].mDataByteSize = (UInt32)_pcmBufferSize;
    _pcmBuffer = NULL;
    _pcmBufferSize = 0;
    return originalBufferSize;
}


#pragma mark ------------------------------------output AAC packet setting----------------------------
/**
 *  Add ADTS header at the beginning of each and every AAC packet.
 *  This is needed as MediaCodec encoder generates a packet of raw
 *  AAC data.
 *
 *  Note the packetLen must count in the ADTS header itself.
 *  See: http://wiki.multimedia.cx/index.php?title=ADTS
 *  Also: http://wiki.multimedia.cx/index.php?title=MPEG-4_Audio#Channel_Configurations
 **/
- (NSData*) adtsDataForPacketLength:(NSUInteger)packetLength
{
    int adtsLength = 7;
    char *packet = malloc(sizeof(char) * adtsLength);
    // Variables Recycled by addADTStoPacket
    int profile = 2;  //AAC LC
    //39=MediaCodecInfo.CodecProfileLevel.AACObjectELD;
    int freqIdx = 4;  //44.1KHz
    int chanCfg = 1;  //MPEG-4 Audio Channel Configuration. 1 Channel front-center
    NSUInteger fullLength = adtsLength + packetLength;
    // fill in ADTS data
    packet[0] = (char)0xFF; // 11111111     = syncword
    packet[1] = (char)0xF9; // 1111 1 00 1  = syncword MPEG-2 Layer CRC
    packet[2] = (char)(((profile-1)<<6) + (freqIdx<<2) +(chanCfg>>2));
    packet[3] = (char)(((chanCfg&3)<<6) + (fullLength>>11));
    packet[4] = (char)((fullLength&0x7FF) >> 3);
    packet[5] = (char)(((fullLength&7)<<5) + 0x1F);
    packet[6] = (char)0xFC;
    NSData *data = [NSData dataWithBytesNoCopy:packet length:adtsLength freeWhenDone:YES];
    return data;
}

@end
