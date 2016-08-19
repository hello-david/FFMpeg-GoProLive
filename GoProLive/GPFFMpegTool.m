//
//  GPFFMpegTool.m
//  GoProLive
//
//  Created by David.Dai on 16/8/19.
//  Copyright © 2016年 David.Dai. All rights reserved.
//

#import "GPFFMpegTool.h"

@implementation GPFFMpegTool

#pragma mark--------------------------ffmpeg setting--------------------------------------
void init_ffmpeg()
{
    av_register_all();
    avformat_network_init();
}

int open_decoder(AVCodecContext **codec_ctx,AVFormatContext *in_fmt_ctx)
{
    int ret,video_index = 0;
    //find input stream codec
    for(int i = 0; i<in_fmt_ctx->nb_streams; i++)
    {
        AVStream *stream = in_fmt_ctx->streams[i];
        AVCodec *codec = avcodec_find_decoder(stream->codecpar->codec_id);
        
        AVCodecContext *ctx = avcodec_alloc_context3(codec);
        avcodec_parameters_to_context(ctx, stream->codecpar);
        if(ctx->codec_type == AVMEDIA_TYPE_VIDEO)
        {
            video_index = i;
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
    
    return video_index;
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
void reset_packet_pts_dts(AVFormatContext *in_fmt_ctx,AVFormatContext *out_fmt_ctx, AVPacket *packet,int stream_video_index,int frame_index,int64_t start_time)
{
    //recalculate pts and dts
    AVRational time_base1 = in_fmt_ctx->streams[stream_video_index]->time_base;
    int64_t calc_duration = (double)AV_TIME_BASE / av_q2d(in_fmt_ctx->streams[stream_video_index]->r_frame_rate);
    packet->pts = (double)(frame_index * calc_duration) / (double)(av_q2d(time_base1) * AV_TIME_BASE);
    packet->dts = packet->pts;
    packet->duration = (double)calc_duration / (double)(av_q2d(time_base1) * AV_TIME_BASE);
    
    //delay pts time
    AVRational time_base = in_fmt_ctx->streams[stream_video_index]->time_base;
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
int decode_sync(AVCodecContext *codec_ctx, AVFrame *frame, int *got_frame, AVPacket *packet)
{
    int ret;
    
    *got_frame = 0;
    
    if (packet) {
        ret = avcodec_send_packet(codec_ctx, packet);
        // In particular, we don't expect AVERROR(EAGAIN), because we read all
        // decoded frames with avcodec_receive_frame() until done.
        if (ret < 0)
            return ret == AVERROR_EOF ? 0 : ret;
    }
    
    ret = avcodec_receive_frame(codec_ctx, frame);
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
+ (UIImage*)converFrameToImage:(AVFrame *)avFrame pixFormat:(int)pixFormat
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
