//
//  GPFFMpegTool.h
//  GoProLive
//
//  Created by David.Dai on 16/8/19.
//  Copyright © 2016年 David.Dai. All rights reserved.
//

#import <Foundation/Foundation.h>
#import <libavformat/avformat.h>
#import <libavutil/mathematics.h>
#import <libavutil/time.h>
#import <libavcodec/avcodec.h>
#import <libswscale/swscale.h>
#import <libavutil/pixfmt.h>
#import <libavutil/imgutils.h>

void init_ffmpeg();
int open_input_ctx          (AVFormatContext **ifmt_ctx, const char* in_filename);
int open_input_ctx_mpegts   (AVFormatContext **ifmt_ctx, const char* in_filename);
int open_output_ctx_rtmp    (AVFormatContext **out_fmt_ctx,  AVFormatContext *ifmt_ctx,const char* out_filename);
int open_decoder            (AVCodecContext  **codec_ctx,    AVFormatContext *in_fmt_ctx);
void reset_packet_pts_dts   (AVFormatContext *in_fmt_ctx,    AVFormatContext *out_fmt_ctx,AVPacket *packet,int stream_video_index,int frame_index,int64_t start_time);
int decode_sync             (AVCodecContext  *codec_ctx,     AVFrame *frame, int *got_frame, AVPacket *packet);
int muxing_stream();

@interface GPFFMpegTool : NSObject

+ (UIImage*)converFrameToImage:(AVFrame *)avFrame pixFormat:(int)pixFormat;

@end
