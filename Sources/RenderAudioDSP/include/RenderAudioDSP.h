#ifndef RENDER_AUDIO_DSP_H
#define RENDER_AUDIO_DSP_H
#include <MediaToolbox/MediaToolbox.h>
#include <stdbool.h>

CF_ASSUME_NONNULL_BEGIN
typedef struct RenderMeter *RenderMeterRef;
typedef struct {
    bool valid;
    unsigned channels;
    double start, end;
    float peak[8], rms[8];
} RenderMeterSnapshot;
RenderMeterRef _Nullable RenderMeterCreate(void);
void RenderMeterRelease(RenderMeterRef meter);
bool RenderMeterAppendRamp(RenderMeterRef meter,double start,double end,float from,float to);
RenderMeterSnapshot RenderMeterRead(RenderMeterRef meter, double seconds);
CF_IMPLICIT_BRIDGING_ENABLED
MTAudioProcessingTapRef _Nullable RenderMeterCreateTap(RenderMeterRef meter) CF_RETURNS_RETAINED;
CF_IMPLICIT_BRIDGING_DISABLED
CF_ASSUME_NONNULL_END
#endif
