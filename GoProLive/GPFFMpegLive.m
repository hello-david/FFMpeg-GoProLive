//
//  GPFFMpegLive.m
//  GoProLive
//
//  Created by David.Dai on 16/8/5.
//  Copyright © 2016年 David.Dai. All rights reserved.
//

#import "GPFFMpegLive.h"
#import "FRHudManager.h"
#import <libavformat/avformat.h>
#import <libavutil/mathematics.h>
#import <libavutil/time.h>
#import <libavcodec/avcodec.h>
#import <libswscale/swscale.h>
#import <libavutil/pixfmt.h>
#import <libavutil/imgutils.h>

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
    
#pragma mark ---------------------environment setting--------------------------------
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        init_ffmpeg();
    });
    
#pragma mark ---------------------input setting--------------------------------
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
    
#pragma mark ---------------------output setting--------------------------------
    if((ret = open_output_ctx_rtmp(&out_fmt_ctx,in_fmt_ctx,out_filename) < 0))
       goto end;
    
    dispatch_async(dispatch_get_main_queue(), ^{
        [[FRHudManager defaultManager] showText:@"Live Start" hideAfter:2];
        [[NSNotificationCenter defaultCenter]postNotificationName:kGoProHackKeepAlive object:nil];
        NSLog(@"start Keep Live Stream");
    });
    
#pragma mark ---------------------open an decoder--------------------------------
    int in_stream_video_index = -1;
    if((ret = open_decoder(&h264decoder_ctx, in_fmt_ctx, &in_stream_video_index)) < 0)
        goto end;
   
#pragma mark ---------------------frame handle--------------------------------
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
            reset_packet_pts_dts(in_fmt_ctx, in_stream_video_index, out_fmt_ctx, packet, frame_index, start_time);
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
                    UIImage * image = [self converFrameToImage:decode_frame pixFormat:h264decoder_ctx->pix_fmt];
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

#pragma mark--------------------------ffmpeg setting--------------------------------------
void init_ffmpeg()
{
    av_register_all();
    avformat_network_init();
}

int open_decoder(AVCodecContext **codec_ctx,AVFormatContext *in_fmt_ctx,int *video_index)
{
    int ret;
    //find input stream codec
    for(int i = 0; i<in_fmt_ctx->nb_streams; i++)
    {
        AVStream *stream = in_fmt_ctx->streams[i];
        AVCodec *codec = avcodec_find_decoder(stream->codecpar->codec_id);
        
        AVCodecContext *ctx = avcodec_alloc_context3(codec);
        avcodec_parameters_to_context(ctx, stream->codecpar);
        if(ctx->codec_type == AVMEDIA_TYPE_VIDEO)
        {
            *video_index = i;
            *codec_ctx = ctx;
            break;
        }
        
        avcodec_free_context(&ctx);
    }
    
    AVCodec	*decoder = avcodec_find_decoder((*codec_ctx)->codec_id);
    if(decoder == NULL){
        printf("Couldn't find Codec.\n");
        return -1;
    }
    if((ret = avcodec_open2((*codec_ctx), decoder,NULL) )<0)
    {
        printf("Couldn't open codec.\n");
        return ret;
    }

    return 0;
}

#pragma mark ---------------------input output format setting-----------------------------------------
int open_input_ctx(AVFormatContext **ifmt_ctx,const char* in_filename)
{
    int ret;
    *ifmt_ctx = avformat_alloc_context();
    if(ifmt_ctx == NULL)
    {
        printf("error avformat_alloc_context \n");
        return  -1;
    }
    
    AVDictionary *inputOpts = NULL;
    av_dict_set(&inputOpts, "timeout", "5000000", 0);//in us
    av_dict_set(&inputOpts, "probesize", "10240", 0);
    
    (*ifmt_ctx) -> probesize = 10 * 1024;
    if ((ret = avformat_open_input(ifmt_ctx, in_filename, NULL, &inputOpts)) < 0)
    {
        printf( "Could not open input file.\n");
        return  -1;
    }
    
    if(!(*ifmt_ctx)->streams)
    {
        printf( "Failed to find stream\n");
        return -1;
    }
    
    (*ifmt_ctx) -> max_analyze_duration = AV_TIME_BASE / 1000;
    if ((ret = avformat_find_stream_info(*ifmt_ctx, 0)) < 0)
    {
        printf( "Failed to retrieve input stream information\n");
        return -1;
    }
    av_dump_format(*ifmt_ctx, 0, in_filename, 0);
    
    return 0;
}

int open_input_ctx_mpegts(AVFormatContext **ifmt_ctx,const char* in_filename)
{
    int ret;
    *ifmt_ctx = avformat_alloc_context();
    if(ifmt_ctx == NULL)
    {
        printf("error avformat_alloc_context \n");
        return  -1;
    }
    
    AVDictionary *inputOpts = NULL;
    av_dict_set(&inputOpts, "timeout", "5000000", 0);//in us
    av_dict_set(&inputOpts, "probesize", "10240", 0);
    AVInputFormat *fmt = av_find_input_format("mpegts");
    
    (*ifmt_ctx) -> probesize = 10 * 1024;
    if ((ret = avformat_open_input(ifmt_ctx, in_filename, fmt, &inputOpts)) < 0)
    {
        printf( "Could not open input file.\n");
        return  -1;
    }
    
    if(!(*ifmt_ctx)->streams)
    {
        printf( "Failed to find stream\n");
        return -1;
    }
    
    (*ifmt_ctx) -> max_analyze_duration = AV_TIME_BASE / 1000;
    if ((ret = avformat_find_stream_info(*ifmt_ctx, 0)) < 0)
    {
        printf( "Failed to retrieve input stream information\n");
        return -1;
    }
    av_dump_format(*ifmt_ctx, 0, in_filename, 0);
    
    return 0;
}

int open_output_ctx_rtmp(AVFormatContext **out_fmt_ctx,AVFormatContext *ifmt_ctx,const char* out_filename)
{
    int ret = 0;

    //open format context
    avformat_alloc_output_context2(out_fmt_ctx, NULL, "flv", out_filename);
    if (!*out_fmt_ctx)
    {
        printf( "Could not create output context\n");
        return ret = AVERROR_UNKNOWN;
    }
    
    //set format context
    for (int i = 0; i < ifmt_ctx->nb_streams; i++)
    {
        AVStream *in_stream = ifmt_ctx->streams[i];
        AVCodec *codec = avcodec_find_decoder(in_stream->codecpar->codec_id);
        AVCodecParameters *para = in_stream->codecpar;
        
        if((para->codec_type == AVMEDIA_TYPE_VIDEO || para->codec_type == AVMEDIA_TYPE_AUDIO) && para->extradata_size > 0)
        {
            //new for output format context
            AVStream *out_stream = avformat_new_stream(*out_fmt_ctx,codec);
            if (!out_stream)
            {
                printf( "Failed allocating output stream\n");
                return ret = AVERROR_UNKNOWN;
            }
            
            ret = avcodec_parameters_copy(out_stream->codecpar, in_stream->codecpar);
            if(ret < 0)
            {
                printf( "Failed to copy context from input to output stream codec context\n");
                return ret;
            }
            
            out_stream->codecpar->codec_tag = 0;
        }
    }
    av_dump_format(*out_fmt_ctx, 0, out_filename, 1);
    
    //open output file with format
    AVOutputFormat *out_fmt = (*out_fmt_ctx)->oformat;
    if (!(out_fmt->flags & AVFMT_NOFILE))
    {
        ret = avio_open(&(*out_fmt_ctx)->pb, out_filename, AVIO_FLAG_WRITE);
        if (ret < 0)
        {
            printf( "Could not open output URL '%s'\n", out_filename);
            return ret;
        }
    }
    ret = avformat_write_header(*out_fmt_ctx, NULL);
    if (ret < 0)
    {
        printf( "Error occurred when opening output URL\n");
        return ret;
    }
    
    return 0;
}

#pragma mark ---------------------H264 Packet dts pts setting-----------------------------------------
void reset_packet_pts_dts(AVFormatContext *in_fmt_ctx,int video_index,AVFormatContext *out_fmt_ctx, AVPacket *packet,int frame_index,int64_t start_time)
{
    //recalculate pts and dts
    AVRational time_base1 = in_fmt_ctx->streams[video_index]->time_base;
    int64_t calc_duration = (double)AV_TIME_BASE / av_q2d(in_fmt_ctx->streams[video_index]->r_frame_rate);
    packet->pts = (double)(frame_index * calc_duration) / (double)(av_q2d(time_base1) * AV_TIME_BASE);
    packet->dts = packet->pts;
    packet->duration = (double)calc_duration / (double)(av_q2d(time_base1) * AV_TIME_BASE);
    
    //delay pts time
    AVRational time_base = in_fmt_ctx->streams[video_index]->time_base;
    AVRational time_base_q = {1,AV_TIME_BASE};
    int64_t pts_time = av_rescale_q(packet->dts, time_base, time_base_q);
    int64_t now_time = av_gettime() - start_time;
    if (pts_time > now_time)
        av_usleep((int)(pts_time - now_time));
    
    AVStream *in_stream = in_fmt_ctx->streams[packet->stream_index];
    AVStream *out_stream = out_fmt_ctx->streams[packet->stream_index];
    
    //convert PTS/DTS
    packet->pts = av_rescale_q_rnd(packet->pts, in_stream->time_base, out_stream->time_base, (AV_ROUND_NEAR_INF|AV_ROUND_PASS_MINMAX));
    packet->dts = av_rescale_q_rnd(packet->dts, in_stream->time_base, out_stream->time_base, (AV_ROUND_NEAR_INF|AV_ROUND_PASS_MINMAX));
    packet->duration = av_rescale_q(packet->duration, in_stream->time_base, out_stream->time_base);
    packet->pos = -1;
}

#pragma mark ------------------------sync decode packet-----------------------------------------
int decode_sync(AVCodecContext *avctx, AVFrame *frame, int *got_frame, AVPacket *pkt)
{
    int ret;
    
    *got_frame = 0;
    
    if (pkt) {
        ret = avcodec_send_packet(avctx, pkt);
        // In particular, we don't expect AVERROR(EAGAIN), because we read all
        // decoded frames with avcodec_receive_frame() until done.
        if (ret < 0)
            return ret == AVERROR_EOF ? 0 : ret;
    }
    
    ret = avcodec_receive_frame(avctx, frame);
    if (ret < 0 && ret != AVERROR(EAGAIN) && ret != AVERROR_EOF)
        return ret;
    if (ret >= 0)
        *got_frame = 1;
    
    return 0;
}

#pragma mark ------------------------async decode packet----------------------------------------
typedef int (*process_frame_cb)(void *ctx, AVFrame *frame);
int decode_async(AVCodecContext *avctx, AVPacket *pkt, process_frame_cb cb, void *priv)
{
    AVFrame *frame = av_frame_alloc();
    int ret;
    
    ret = avcodec_send_packet(avctx, pkt);
    // Again EAGAIN is not expected
    if (ret < 0)
        goto out;
    
    while (!ret) {
        ret = avcodec_receive_frame(avctx, frame);
        if (!ret)
            ret = cb(priv, frame);
    }
    
    out:
    av_frame_free(&frame);
    if (ret == AVERROR(EAGAIN))
        return 0;
    return ret;
}

#pragma mark ------------------------trans frame to image----------------------------------------
- (UIImage*)converFrameToImage:(AVFrame *)avFrame pixFormat:(int)pixFormat
{
    float width = avFrame->width;
    float height = avFrame->height;
    
    //use this function instead of av_picture_alloc()
    AVFrame *rgbPicture = av_frame_alloc();
    Byte *rgbBuffer = NULL;
    {
        int pictureSize = av_image_get_buffer_size(AV_PIX_FMT_RGB24, width + 1, height + 1, 16);
        rgbBuffer = malloc(pictureSize);
        memset(rgbBuffer, 0, pictureSize);
        av_image_fill_arrays(rgbPicture->data, rgbPicture->linesize, rgbBuffer, AV_PIX_FMT_RGB24, width, height, 1);
    }
    
    //sws picture
    struct SwsContext * imgConvertCtx = sws_getContext(avFrame->width,
                                                       avFrame->height,
                                                       AV_PIX_FMT_YUV420P,
                                                       width,
                                                       height,
                                                       AV_PIX_FMT_RGB24,
                                                       SWS_FAST_BILINEAR,
                                                       NULL,
                                                       NULL,
                                                       NULL);
    if(imgConvertCtx == nil) return nil;
    sws_scale(imgConvertCtx,
              (uint8_t const * const *)avFrame->data,
              avFrame->linesize,
              0,
              avFrame->height,
              rgbPicture->data,
              rgbPicture->linesize);
    sws_freeContext(imgConvertCtx);
    
    //conver rgb24 to UIImage
    CGBitmapInfo bitmapInfo = kCGBitmapByteOrderDefault;
    CFDataRef data = CFDataCreate(kCFAllocatorDefault,
                                  rgbPicture->data[0],
                                  rgbPicture->linesize[0] * height);
    
    CGDataProviderRef provider = CGDataProviderCreateWithCFData(data);
    CGColorSpaceRef colorSpace = CGColorSpaceCreateDeviceRGB();
    CGImageRef cgImage = CGImageCreate(width,
                                       height,
                                       8,
                                       24,
                                       rgbPicture->linesize[0],
                                       colorSpace,
                                       bitmapInfo,
                                       provider,
                                       NULL,
                                       NO,
                                       kCGRenderingIntentDefault);
    
    UIImage *image = [UIImage imageWithCGImage:cgImage];
    
    //release buffer
    CGImageRelease(cgImage);
    CGColorSpaceRelease(colorSpace);
    CGDataProviderRelease(provider);
    CFRelease(data);
    if(rgbBuffer)free(rgbBuffer);
    av_frame_free(&rgbPicture);
    
    return image;
}
@end
