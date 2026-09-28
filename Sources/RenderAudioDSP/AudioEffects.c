#include "AudioEffects.h"
#include <math.h>
#include <stdlib.h>
#include <string.h>
#include <float.h>

#define EFFECT_LIMIT 16
#define CHANNEL_LIMIT 8
#define PI 3.14159265358979323846
typedef struct { double b0,b1,b2,a1,a2; } Biquad;
typedef struct { RenderAudioEffectDescriptor descriptor; Biquad bands[3]; double attack,release,level,closed,makeup,detectorDecay; } PreparedEffect;
typedef struct { double start,end; size_t count; PreparedEffect effects[EFFECT_LIMIT]; } Segment;
typedef struct { double z1[3][CHANNEL_LIMIT],z2[3][CHANNEL_LIMIT],envelope,gain; } EffectState;
struct RenderAudioProgram {
    Segment *segments; size_t count,capacity,active;
    double sampleRate,nextTime;
    EffectState state[EFFECT_LIMIT];
};
static double clamp(double x,double lo,double hi) { return fmax(lo,fmin(hi,x)); }
static double dbGain(double db) { return pow(10,db/20); }
static double coefficient(double ms,double sampleRate) { return exp(-1/(fmax(0.1,ms)*0.001*sampleRate)); }
static Biquad eqBand(double gain,double frequency,double q,double rate,int kind) {
    if (fabs(gain)<1e-12) return (Biquad){1,0,0,0,0};
    double A=pow(10,gain/40),w=2*PI*clamp(frequency,1,rate*0.45)/rate,c=cos(w),s=sin(w);
    double alpha=s/(2*q),b0,b1,b2,a0,a1,a2;
    if (kind==1) { b0=1+alpha*A;b1=-2*c;b2=1-alpha*A;a0=1+alpha/A;a1=-2*c;a2=1-alpha/A; }
    else {
        double beta=2*sqrt(A)*s/sqrt(2);
        if (kind==0) {
            b0=A*((A+1)-(A-1)*c+beta);b1=2*A*((A-1)-(A+1)*c);b2=A*((A+1)-(A-1)*c-beta);
            a0=(A+1)+(A-1)*c+beta;a1=-2*((A-1)+(A+1)*c);a2=(A+1)+(A-1)*c-beta;
        } else {
            b0=A*((A+1)+(A-1)*c+beta);b1=-2*A*((A-1)+(A+1)*c);b2=A*((A+1)+(A-1)*c-beta);
            a0=(A+1)-(A-1)*c+beta;a1=2*((A-1)-(A+1)*c);a2=(A+1)-(A-1)*c-beta;
        }
    }
    return (Biquad){b0/a0,b1/a0,b2/a0,a1/a0,a2/a0};
}
RenderAudioProgramRef RenderAudioProgramCreate(void) {
    RenderAudioProgramRef program=calloc(1,sizeof(struct RenderAudioProgram));
    if (program) { program->active=SIZE_MAX;program->nextTime=NAN;program->sampleRate=48000; }
    return program;
}
void RenderAudioProgramDestroy(RenderAudioProgramRef p) { if (p) { free(p->segments);free(p); } }
bool RenderAudioProgramAppend(RenderAudioProgramRef p,double start,double end,const RenderAudioEffectDescriptor *effects,size_t count) {
    if (!p || !isfinite(start)||!isfinite(end)||end<=start||count>EFFECT_LIMIT||(count&&!effects)) return false;
    if (p->count && start<p->segments[p->count-1].end-1e-7) return false;
    for (size_t i=0;i<count;i++) {
        if (effects[i].kind>3) return false;
        for (unsigned v=0;v<8;v++) if (!isfinite(effects[i].values[v])) return false;
    }
    if (p->count==p->capacity) {
        size_t capacity=p->capacity ? p->capacity*2 : 8;
        Segment *storage=realloc(p->segments,capacity*sizeof(Segment));if (!storage) return false;
        p->segments=storage;p->capacity=capacity;
    }
    Segment *segment=&p->segments[p->count++];memset(segment,0,sizeof(*segment));segment->start=start;segment->end=end;segment->count=count;
    for (size_t i=0;i<count;i++) segment->effects[i].descriptor=effects[i];
    return true;
}
void RenderAudioProgramPrepare(RenderAudioProgramRef p,double sampleRate) {
    if (!p) return;
    p->sampleRate=isfinite(sampleRate)&&sampleRate>0 ? sampleRate : 48000;p->active=SIZE_MAX;p->nextTime=NAN;
    for (size_t s=0;s<p->count;s++) for (size_t i=0;i<p->segments[s].count;i++) {
        PreparedEffect *effect=&p->segments[s].effects[i];double *v=effect->descriptor.values;
        effect->level=dbGain(v[0]); effect->closed=dbGain(v[1]);effect->makeup=dbGain(v[5]);effect->detectorDecay=exp(-1/(0.05*p->sampleRate));
        switch (effect->descriptor.kind) {
        case 0:
            for (int band=0;band<3;band++) effect->bands[band]=eqBand(v[band],v[band+3],fmax(0.1,v[6]),p->sampleRate,band);
            break;
        case 1: case 3: effect->attack=coefficient(v[2],p->sampleRate);effect->release=coefficient(v[3],p->sampleRate);break;
        case 2: effect->release=coefficient(v[1],p->sampleRate);break;
        }
    }
}
static size_t findSegment(RenderAudioProgramRef p,double time) {
    size_t lo=0,hi=p->count;
    while (lo<hi) { size_t mid=lo+(hi-lo)/2;if (p->segments[mid].start<=time) lo=mid+1;else hi=mid; }
    return lo && time<p->segments[lo-1].end ? lo-1 : SIZE_MAX;
}
static void reset(RenderAudioProgramRef p,size_t segment) {
    p->active=segment;memset(p->state,0,sizeof(p->state));
    for (size_t i=0;i<EFFECT_LIMIT;i++) p->state[i].gain=1;
}
void RenderAudioProgramProcess(RenderAudioProgramRef p,float **channels,const unsigned *strides,unsigned channelCount,size_t frames,double start,double duration) {
    if (!p||!frames||!channelCount||channelCount>CHANNEL_LIMIT||!isfinite(start)||!isfinite(duration)||duration<=0) return;
    size_t segment=findSegment(p,start);
    if (segment==SIZE_MAX) {
        size_t lo=0,hi=p->count;
        while (lo<hi) { size_t mid=lo+(hi-lo)/2;if (p->segments[mid].start<start) lo=mid+1;else hi=mid; }
        if (lo==p->count || p->segments[lo].start>=start+duration) { reset(p,SIZE_MAX);p->nextTime=start+duration;return; }
    }
    if (segment!=p->active || !isfinite(p->nextTime) || fabs(start-p->nextTime)>1/p->sampleRate) reset(p,segment);
    for (size_t f=0;f<frames;f++) {
        double time=start+duration*(double)f/(double)frames;
        if (segment==SIZE_MAX || time>=p->segments[segment].end) { size_t next=findSegment(p,time);if (next!=segment) { segment=next;reset(p,next); } }
        if (segment==SIZE_MAX) continue;
        double sample[CHANNEL_LIMIT];for (unsigned c=0;c<channelCount;c++) { double x=channels[c][f*strides[c]];sample[c]=isfinite(x)?x:0; }
        Segment *current=&p->segments[segment];
        for (size_t i=0;i<current->count;i++) {
            PreparedEffect *effect=&current->effects[i];EffectState *state=&p->state[i];double *v=effect->descriptor.values;
            if (effect->descriptor.kind==0) {
                for (unsigned c=0;c<channelCount;c++) for (unsigned b=0;b<3;b++) {
                    Biquad k=effect->bands[b];double x=sample[c],y=k.b0*x+state->z1[b][c];
                    state->z1[b][c]=k.b1*x-k.a1*y+state->z2[b][c];state->z2[b][c]=k.b2*x-k.a2*y;
                    if (fabs(state->z1[b][c])<1e-20) state->z1[b][c]=0;
                    if (fabs(state->z2[b][c])<1e-20) state->z2[b][c]=0;
                    sample[c]=y;
                }
                continue;
            }
            double peak=0;for (unsigned c=0;c<channelCount;c++) peak=fmax(peak,fabs(sample[c]));
            double gain=1;
            if (effect->descriptor.kind==1) {
                double smoothing=peak>state->envelope ? effect->attack : effect->release;
                state->envelope=peak+(state->envelope-peak)*smoothing;
                double over=20*log10(fmax(1e-12,state->envelope))-v[0],knee=v[4],reduction=0;
                if (knee>0 && over>-knee/2 && over<knee/2) reduction=(1/fmax(1,v[1])-1)*pow(over+knee/2,2)/(2*knee);
                else if (over>=knee/2) reduction=(1/fmax(1,v[1])-1)*over;
                gain=dbGain(reduction)*effect->makeup;
            } else if (effect->descriptor.kind==2) {
                double target=fmin(1,effect->level/fmax(1e-12,peak));
                state->gain=target<state->gain ? target : target+(state->gain-target)*effect->release;gain=state->gain;
            } else {
                state->envelope=fmax(peak,state->envelope*effect->detectorDecay);
                double target=state->envelope>=effect->level ? 1 : effect->closed;
                double smoothing=target>state->gain ? effect->attack : effect->release;
                state->gain=target+(state->gain-target)*smoothing;gain=state->gain;
            }
            for (unsigned c=0;c<channelCount;c++) sample[c]*=gain;
        }
        for (unsigned c=0;c<channelCount;c++) channels[c][f*strides[c]]=(float)(isfinite(sample[c]) ? clamp(sample[c],-FLT_MAX,FLT_MAX) : 0);
    }
    p->nextTime=start+duration;
}
