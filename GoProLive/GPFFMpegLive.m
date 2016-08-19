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

@implementation GPFFMpegLive
{
    NSThread            *_pushThread;
}

- (instancetype)init
{
    if(self = [super init]){
        [[NSNotificationCenter defaultCenter]addObserver:self selector:@selector(getMicAACSound:) name:@"aacAudio" object:nil];
        _pushToServer = YES;
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
        sprintf(out_filename,"%s","rtmp://52.68.136.211:1935/live/ffmpegTest");
    
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
        [[FRHudManager defaultManager]showLoadingWithText:@"Waiting For Live Stream"];
    });
    
    AVFormatContext *in_fmt_ctx = NULL;
    AVCodecContext	*h264decoder_ctx = NULL;
    AVFormatContext *out_fmt_ctx = NULL;

//    if((ret = open_input_ctx_mpegts(&in_fmt_ctx,in_filename)) < 0)
//        goto end;
    if((ret = open_input_ctx(&in_fmt_ctx,in_filename)) < 0)
        goto end;
    
    //output setting
    if((ret = open_output_ctx_rtmp(&out_fmt_ctx,in_fmt_ctx,out_filename) < 0))
       goto end;
    
    dispatch_async(dispatch_get_main_queue(), ^{
        [[FRHudManager defaultManager] showText:@"Live Start" hideAfter:2];
        [[NSNotificationCenter defaultCenter]postNotificationName:kGoProHackKeepAlive object:nil];
        NSLog(@"start Keep Live Stream");
    });
    
    //open an decoder
    int in_stream_video_index = -1;
    if((in_stream_video_index = open_decoder(&h264decoder_ctx, in_fmt_ctx)) < 0)
        goto end;
   
    //frame handle
    int64_t start_time = av_gettime();
    int frame_index=0;
    while (![_pushThread isCancelled])
    {
        AVPacket *packet = av_packet_alloc();
        //get an AVPacket
        ret = av_read_frame(in_fmt_ctx, packet);
        if (ret < 0)break;
        
        //h264 video
        if(packet->stream_index == in_stream_video_index)
        {
            printf("frame= %d size= %dKB\n",frame_index ,packet->size);
            reset_packet_pts_dts(in_fmt_ctx, out_fmt_ctx, packet,in_stream_video_index, frame_index, start_time);
            frame_index++;
            
            //decode
            AVFrame	*decode_frame = av_frame_alloc();
            if(packet->stream_index == in_stream_video_index && h264decoder_ctx)
            {
                int got_frame = 0;
                ret = decode_sync(h264decoder_ctx, decode_frame, &got_frame, packet);
                if(ret < 0 )break;
                
                //flash
                if(decode_frame->pict_type != AV_PICTURE_TYPE_NONE)
                {
                    UIImage * image = [GPFFMpegTool converFrameToImage:decode_frame pixFormat:h264decoder_ctx->pix_fmt];
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
                ret = av_interleaved_write_frame(out_fmt_ctx,packet);
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
                ret = av_interleaved_write_frame(out_fmt_ctx,packet);
                if (ret < 0)
                {
                    printf( "Error muxing packet\n");
                    break;
                }
            }
            av_packet_free(&packet);
        }
    }
    
    //norml end write file trailer
    av_write_trailer(out_fmt_ctx);
    
end:
    if(h264decoder_ctx)
    {
        avcodec_close(h264decoder_ctx);
    }
    
    if(in_fmt_ctx)
    {
        if(in_fmt_ctx->iformat && !(in_fmt_ctx->iformat) & AVFMT_NOFILE)
            avio_close(in_fmt_ctx->pb);
        avformat_close_input(&in_fmt_ctx);
        avformat_free_context(in_fmt_ctx);
    }
    
    if(out_fmt_ctx)
    {
        if (out_fmt_ctx && !(out_fmt_ctx->oformat->flags & AVFMT_NOFILE))
            avio_close(out_fmt_ctx->pb);
        avformat_free_context(out_fmt_ctx);
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
