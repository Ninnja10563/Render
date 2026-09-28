#ifndef RENDER_AUDIO_EFFECTS_H
#define RENDER_AUDIO_EFFECTS_H
#include <stddef.h>
#include <stdbool.h>
#include <stdint.h>
// 0 EQ [low/mid/high dB, low/mid/high Hz, Q]; 1 compressor [threshold,ratio,attack,release,knee,makeup];
// 2 sample-peak limiter [ceiling,release]; 3 gate [threshold,closed gain,attack,release]. Times are ms, levels dB.
typedef struct { uint32_t kind; double values[8]; } RenderAudioEffectDescriptor;
typedef struct RenderAudioProgram *RenderAudioProgramRef;
RenderAudioProgramRef RenderAudioProgramCreate(void);
void RenderAudioProgramDestroy(RenderAudioProgramRef program);
bool RenderAudioProgramAppend(RenderAudioProgramRef program,double start,double end,const RenderAudioEffectDescriptor *effects,size_t count,bool continuous);
void RenderAudioProgramPrepare(RenderAudioProgramRef program,double sampleRate);
void RenderAudioProgramProcess(RenderAudioProgramRef program,float **channels,const unsigned *strides,unsigned channelCount,size_t frames,double start,double duration);
#endif
