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

int open_input_video_decoder(AVCodecContext **codec_ctx,AVFormatContext *in_fmt_ctx)
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

int open_output_ctx_rtmp(AVFormatContext **out_fmt_ctx,AVFormatContext *ifmt_ctx,const char* out_filename,bool use_phone_mic)
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
        
        bool media;
        if(use_phone_mic)
            (para->codec_type == AVMEDIA_TYPE_VIDEO) ? (media = YES):(media = NO);
        else
            ((para->codec_type == AVMEDIA_TYPE_VIDEO || para->codec_type == AVMEDIA_TYPE_AUDIO)) ? (media = YES):(media = NO);
        
        if(media && para->extradata_size > 0)
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
    
    if(use_phone_mic)
        add_aac_phone_audio_stream(out_fmt_ctx, out_filename);
    
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

int add_aac_phone_audio_stream(AVFormatContext **context,const char* out_filename)
{
    AVCodec *codec = avcodec_find_encoder(AV_CODEC_ID_AAC);
    AVCodecContext *codec_ctx = avcodec_alloc_context3(codec);
    if (!codec){
        printf("Could not find encoder for '%s'\n",avcodec_get_name(AV_CODEC_ID_AAC));
    }
    
    AVStream *stream = avformat_new_stream(*context, codec);
    if (!stream){
        printf("Could not allocate stream\n");
    }
    
    stream->id = (*context)->nb_streams -1;
    avcodec_parameters_to_context(codec_ctx, stream->codecpar);
    switch (codec->type)
    {
        case AVMEDIA_TYPE_AUDIO:
            codec_ctx->codec_id     = AV_CODEC_ID_AAC;
            codec_ctx->codec_type   = AVMEDIA_TYPE_AUDIO;
            codec_ctx->sample_fmt   = codec->sample_fmts ? codec->sample_fmts[0] : AV_SAMPLE_FMT_FLTP;
            codec_ctx->bit_rate     = 128033;
            codec_ctx->sample_rate  = 44100;
            codec_ctx->channel_layout = AV_CH_LAYOUT_STEREO;
            codec_ctx->channels     = av_get_channel_layout_nb_channels(codec_ctx->channel_layout);
            stream->time_base       = (AVRational){ 1,codec_ctx->sample_rate};
            break;
        default:
            break;
    }
    avcodec_parameters_from_context(stream->codecpar, codec_ctx);
    
    /* Some formats want stream headers to be separate. */
    if ((*context)->oformat->flags & AVFMT_GLOBALHEADER)
        codec_ctx->flags |= CODEC_FLAG_GLOBAL_HEADER;
    
    av_dump_format(*context, 0, out_filename, 1);
    return 0;
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

+ (AVPacket *)encodeToAAC:(CMSampleBufferRef)sampleBuffer outputContext:(AVFormatContext *)context
{
    CMSampleTimingInfo timing_info;
    CMSampleBufferGetSampleTimingInfo(sampleBuffer, 0, &timing_info);
    double  pts=0;
    double  dts=0;
    AVCodecContext *c;
    int got_packet, ret;
    c = audio_st->codec;
    CMItemCount numSamples = CMSampleBufferGetNumSamples(sampleBuffer);
    
    NSUInteger channelIndex = 0;
    
    //get pcm data
    CMBlockBufferRef audioBlockBuffer = CMSampleBufferGetDataBuffer(sampleBuffer);
    size_t audioBlockBufferOffset = (channelIndex * numSamples * sizeof(SInt16));
    size_t lengthAtOffset = 0;
    size_t totalLength = 0;
    SInt16 *samples = NULL;
    CMBlockBufferGetDataPointer(audioBlockBuffer, audioBlockBufferOffset, &lengthAtOffset, &totalLength, (char **)(&samples));
    
    const AudioStreamBasicDescription *audioDescription = CMAudioFormatDescriptionGetStreamBasicDescription(CMSampleBufferGetFormatDescription(sampleBuffer));
    
    SwrContext *swr = swr_alloc();
    int in_smprt = (int)audioDescription->mSampleRate;
    av_opt_set_int(swr, "in_channel_layout",  AV_CH_LAYOUT_MONO, 0);
    av_opt_set_int(swr, "in_channel_count",   audioDescription->mChannelsPerFrame,  0);
    av_opt_set_int(swr, "in_sample_rate",     audioDescription->mSampleRate,0);
    av_opt_set_sample_fmt(swr, "in_sample_fmt",  AV_SAMPLE_FMT_S16, 0);
    
    av_opt_set_int(swr, "out_channel_layout", audio_st->codec->channel_layout,  0);
    av_opt_set_int(swr, "out_channel_count", 1,  0);
    av_opt_set_int(swr, "out_channel_layout", audio_st->codec->channel_layout,  0);
    av_opt_set_int(swr, "out_sample_rate",    audio_st->codec->sample_rate,0);
    av_opt_set_sample_fmt(swr, "out_sample_fmt", audio_st->codec->sample_fmt,  0);
    swr_init(swr);
    
    uint8_t **input = NULL;
    int src_linesize;
    int in_samples = (int)numSamples;
    ret = av_samples_alloc_array_and_samples(&input, &src_linesize, audioDescription->mChannelsPerFrame, in_samples, AV_SAMPLE_FMT_S16P, 0);
    
    *input=(uint8_t*)samples;
    uint8_t *output=NULL;
    
    int out_samples = av_rescale_rnd(swr_get_delay(swr, in_smprt) +in_samples, (int)audio_st->codec->sample_rate, in_smprt, AV_ROUND_UP);
    
    av_samples_alloc(&output, NULL, audio_st->codec->channels, out_samples, audio_st->codec->sample_fmt, 0);
    in_samples = (int)numSamples;
    out_samples = swr_convert(swr, &output, out_samples, (const uint8_t **)input, in_samples);
    
    aFrame->nb_samples =(int) out_samples;
    
    ret = avcodec_fill_audio_frame(aFrame, audio_st->codec->channels, audio_st->codec->sample_fmt,
                                   (uint8_t *)output,
                                   (int) out_samples *
                                   av_get_bytes_per_sample(audio_st->codec->sample_fmt) *
                                   audio_st->codec->channels, 1);
    if (ret < 0)
    {
        fprintf(stderr, "Error fill audio frame: %s\n", av_err2str(ret));
    }
    aFrame->channel_layout = audio_st->codec->channel_layout;
    aFrame->channels=audio_st->codec->channels;
    aFrame->sample_rate= audio_st->codec->sample_rate;
    
    if (timing_info.presentationTimeStamp.timescale!=0)
        pts=(double) timing_info.presentationTimeStamp.value/timing_info.presentationTimeStamp.timescale;
    
    
    aFrame->pts = pts*audio_st->time_base.den;
    aFrame->pts = av_rescale_q(aFrame->pts, audio_st->time_base, audio_st->codec->time_base);
    
    ret = avcodec_encode_audio2(c, &pkt2, aFrame, &got_packet);
    
    if (ret < 0)
    {
        fprintf(stderr, "Error encoding audio frame: %s\n", av_err2str(ret));
    }
    swr_free(&swr);
    
    if (got_packet)
    {
        pkt2.stream_index = audio_st->index;
        
        // Write the compressed frame to the media file.
        ret = av_interleaved_write_frame(pFormatCtx, &pkt2);
        if (ret != 0)
        {
            fprintf(stderr, "Error while writing audio frame: %s\n", av_err2str(ret));
            av_free_packet(&pkt2);
        }
    }
}

@end
