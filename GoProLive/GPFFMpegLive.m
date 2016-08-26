//
//  GPFFMpegLive.m
//  GoProLive
//
//  Created by David.Dai on 16/8/5.
//  Copyright © 2016年 David.Dai. All rights reserved.
//

#import "GPFFMpegLive.h"
#import "FRHudManager.h"
#import "GPFFMpegTool.h"

@interface GPFFMpegLive()

@property(atomic) NSMutableArray *audioPacketArray;

@end

@implementation GPFFMpegLive
{
    NSThread            *_pushThread;
    FFmpegLiveTool      _liveStream;
    NSLock              *_audioLock;
}

- (instancetype)init
{
    if(self = [super init]){
        [[NSNotificationCenter defaultCenter]addObserver:self selector:@selector(getMicAACSound:) name:@"aacAudio" object:nil];
        _pushToServer = YES;
        _audioPacketArray = [[NSMutableArray alloc]init];
        _audioLock = [[NSLock alloc]init];
    }
    return self;
}

- (void)stopLive
{
    if(!_pushThread.finished)
        [_pushThread cancel];
}

- (void)startLive:(NSString *)serverUrl
{
    if(!_pushThread.finished)
        [_pushThread cancel];
    
    if(_pushThread.finished || !_pushThread)
    {
        _pushThread = [[NSThread alloc]initWithTarget:self selector:@selector(pushGoProPreview:) object:serverUrl];
        [_pushThread start];
    }
}

- (void)getMicAACSound:(NSNotification *)notice
{
    if(!notice.object)return;
    [_audioLock lock];
    [_audioPacketArray addObject:notice.object];
    [_audioLock unlock];
}

- (void)pushGoProPreview:(NSString *)serverUrl
{
    char out_filename[500] = {0};
    char in_filename[500]={0};
    int ret;
    
    sprintf(in_filename,"%s", "udp://10.5.5.9:8554");
    if(serverUrl)
        sprintf(out_filename,"%s",[serverUrl UTF8String]);
    else
        sprintf(out_filename,"%s","rtmp://192.168.8.21:1935/live/ffmpegTest");
    
    char input_str_full[500]={0};
    NSString *input_str= [NSString stringWithFormat:@"resource.bundle/%@",@"war3end.mp4"];
    NSString *input_nsstr=[[[NSBundle mainBundle]resourcePath] stringByAppendingPathComponent:input_str];
    sprintf(input_str_full,"%s",[input_nsstr UTF8String]);
    strcpy(in_filename,input_str_full);
    
    printf("Input Path:%s\n",in_filename);
    printf("Output Path:%s\n",out_filename);
    
    //environment setting
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        init_ffmpeg();
    });
    
    //input setting
    dispatch_async(dispatch_get_main_queue(), ^{
        [[FRHudManager defaultManager] showLoadingWithText:@"Waiting For Live Stream"];
    });
    
//    if((ret = open_input_ctx_mpegts(&in_fmt_ctx,in_filename)) < 0)
//        goto end;
    if((ret = open_input_ctx(&_liveStream.inputFormat,in_filename)) < 0)
        goto end;
    
    //output setting
    if((ret = open_output_ctx_rtmp(&_liveStream.outputFormat,_liveStream.inputFormat,out_filename,YES) < 0))
       goto end;
    
    dispatch_async(dispatch_get_main_queue(), ^{
        [[FRHudManager defaultManager] showText:@"Live Start" hideAfter:2];
        [[NSNotificationCenter defaultCenter]postNotificationName:kGoProHackKeepAlive object:nil];
        NSLog(@"start Keep Live Stream");
    });
    
    //open an decoder
    int in_stream_video_index = -1;
    if((in_stream_video_index = open_input_video_decoder(&_liveStream.h264Decoder, _liveStream.inputFormat)) < 0)
        goto end;
    
    //frame handle
    int64_t start_time = av_gettime();
    int video_frame_index = 0;
    while (![_pushThread isCancelled])
    {
        AVPacket *packet = av_packet_alloc();
        //get an AVPacket
        ret = av_read_frame(_liveStream.inputFormat, packet);
        if (ret < 0)break;
        
        //h264 video
        if(packet->stream_index == in_stream_video_index)
        {
            printf("frame= %d size= %dKB\n",video_frame_index ,packet->size);
            reset_video_packet_pts_dts(_liveStream.inputFormat, _liveStream.outputFormat, packet,video_frame_index, start_time);
            video_frame_index++;
            
            //decode
            AVFrame	*decode_frame = av_frame_alloc();
            if(packet->stream_index == in_stream_video_index && _liveStream.h264Decoder)
            {
                int got_frame = 0;
                ret = decode_sync(_liveStream.h264Decoder, decode_frame, &got_frame, packet);
                if(ret < 0 )break;
                
                //flash
                if(decode_frame->pict_type != AV_PICTURE_TYPE_NONE)
                {
                    UIImage *image = [GPFFMpegTool converPixelToImage:[GPFFMpegTool converFrameToPixel:decode_frame]];
                    if (image)
                        dispatch_async(dispatch_get_main_queue(), ^{
                            [[NSNotificationCenter defaultCenter] postNotificationName:@"reflash" object:image];
                        });
                }
            }
            av_frame_free(&decode_frame);
            
            //push to server
            if(_pushToServer)
            {
                ret = av_interleaved_write_frame(_liveStream.outputFormat,packet);
                if (ret < 0)
                {
                    printf( "Error muxing packet\n");
                    break;
                }
            }
            av_packet_free(&packet);
        }
        
        //aac audio
        else
        {
            if(_pushToServer)
            {
                ret = av_interleaved_write_frame(_liveStream.outputFormat,packet);
                if (ret < 0)
                {
                    printf( "Error muxing packet\n");
                    break;
                }
            }
            av_packet_free(&packet);
        }
        
//        if(_audioPacketArray.count)
//        {
//            [_audioLock lock];
//            for(int i = 0;i < _audioPacketArray.count;i++)
//            {
//                CMSampleBufferRef buffer = (__bridge CMSampleBufferRef)([_audioPacketArray objectAtIndex:i]);
//                AVPacket *pack = [GPFFMpegTool encodeToAAC:buffer context:_liveStream.outputFormat];
//                if(pack)
//                {
//                    if(_pushToServer)
//                    {
//                        ret = av_interleaved_write_frame(_liveStream.outputFormat,pack);
//                        if (ret < 0)
//                        {
//                            printf( "Error muxing packet\n");
//                            break;
//                        }
//                    }
//                    av_packet_free(&pack);
//                }
//            }
//            [_audioPacketArray removeAllObjects];
//            [_audioLock unlock];
//        }
    }
    
    //norml end write file trailer
    av_write_trailer(_liveStream.outputFormat);
    
end:
    if(_liveStream.h264Decoder)
    {
        avcodec_close(_liveStream.h264Decoder);
    }
    
    if(_liveStream.inputFormat)
    {
        if(_liveStream.inputFormat->iformat && !(_liveStream.inputFormat->iformat) & AVFMT_NOFILE)
            avio_close(_liveStream.inputFormat->pb);
        avformat_close_input(&_liveStream.inputFormat);
        avformat_free_context(_liveStream.inputFormat);
    }
    
    if(_liveStream.outputFormat)
    {
        if (_liveStream.outputFormat && !(_liveStream.outputFormat->oformat->flags & AVFMT_NOFILE))
            avio_close(_liveStream.outputFormat->pb);
        avformat_free_context(_liveStream.outputFormat);
    }
    
    if (ret < 0 && ret != AVERROR_EOF)
    {
        dispatch_async(dispatch_get_main_queue(), ^{
            [[FRHudManager defaultManager] showText:[NSString stringWithFormat:@"Live Stream Error"] hideAfter:2];
            [[NSNotificationCenter defaultCenter]postNotificationName:kGoProHackStopAlvie object:nil];
            NSLog(@"stop Keep Live Stream");
        });
    }
    
    else if(ret == AVERROR_EOF)
    {
        dispatch_async(dispatch_get_main_queue(), ^{
            [[FRHudManager defaultManager] hide:YES];
            [[NSNotificationCenter defaultCenter]postNotificationName:kGoProHackStopAlvie object:nil];
        });
    }
    
    else
    {
        dispatch_async(dispatch_get_main_queue(), ^{
            [[FRHudManager defaultManager] showText:@"Stop Live" hideAfter:2];
            [[NSNotificationCenter defaultCenter]postNotificationName:kGoProHackStopAlvie object:nil];
            NSLog(@"stop Keep Live Stream");
        });
    }
    
    [NSThread exit];
}
@end
