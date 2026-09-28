#include "RenderAudioDSP.h"
#include <stdatomic.h>
#include <stdlib.h>
#include <string.h>
#include <math.h>

// Samples stay on the audio thread. A bounded atomic ring publishes measurements,
// allowing UI reads at the player's clock even when decoding runs ahead of playback.
#define RENDER_METER_SLOTS 256
_Static_assert(ATOMIC_INT_LOCK_FREE == 2 && ATOMIC_LLONG_LOCK_FREE == 2, "Audio metering requires lock-free atomics");
typedef struct {
    atomic_ullong sequence, start, end;
    atomic_uint channels, peak[8], rms[8];
} MeterSlot;
typedef struct { double start, end; float from, to; } MeterRamp;
struct RenderMeter {
    atomic_uint references;
    unsigned long long writeIndex;
    MeterRamp *ramps; size_t rampCount, rampCapacity;
    bool supported;
    AudioStreamBasicDescription format;
    MeterSlot *slots;
    RenderAudioProgramRef program;
    atomic_bool processingFailed;
};
static unsigned floatBits(float value) { unsigned bits; memcpy(&bits,&value,sizeof(bits)); return bits; }
static float bitsFloat(unsigned bits) { float value; memcpy(&value,&bits,sizeof(value)); return value; }
static unsigned long long doubleBits(double value) { unsigned long long bits; memcpy(&bits,&value,sizeof(bits)); return bits; }
static double bitsDouble(unsigned long long bits) { double value; memcpy(&value,&bits,sizeof(value)); return value; }
RenderMeterRef RenderMeterCreate(bool measuring) {
    RenderMeterRef meter = calloc(1,sizeof(struct RenderMeter));
    if (!meter) return NULL;
    atomic_init(&meter->references,1);atomic_init(&meter->processingFailed,false);
    if (!measuring) return meter;
    meter->slots=calloc(RENDER_METER_SLOTS,sizeof(MeterSlot));
    if (!meter->slots) { free(meter);return NULL; }
    for (unsigned i=0;i<RENDER_METER_SLOTS;i++) {
        MeterSlot *slot = &meter->slots[i];
        atomic_init(&slot->sequence,0); atomic_init(&slot->start,0); atomic_init(&slot->end,0); atomic_init(&slot->channels,0);
        for (unsigned c=0;c<8;c++) { atomic_init(&slot->peak[c],0); atomic_init(&slot->rms[c],0); }
    }
    return meter;
}
void RenderMeterRelease(RenderMeterRef meter) {
    if (atomic_fetch_sub_explicit(&meter->references,1,memory_order_acq_rel)==1) { free(meter->ramps); free(meter->slots); RenderAudioProgramDestroy(meter->program); free(meter); }
}
// Called only while compiling a composition, before the tap is used. Never on the audio thread.
bool RenderMeterAppendRamp(RenderMeterRef meter,double start,double end,float from,float to) {
    if (!isfinite(start) || !isfinite(end) || end <= start || !isfinite(from) || !isfinite(to)) return false;
    if (meter->rampCount && start < meter->ramps[meter->rampCount-1].start) return false;
    if (meter->rampCount == meter->rampCapacity) {
        size_t capacity = meter->rampCapacity ? meter->rampCapacity*2 : 16;
        MeterRamp *storage = realloc(meter->ramps,capacity*sizeof(MeterRamp));
        if (!storage) return false;
        meter->ramps = storage; meter->rampCapacity = capacity;
    }
    meter->ramps[meter->rampCount++] = (MeterRamp){start,end,from,to}; return true;
}
static size_t rampIndex(RenderMeterRef meter,double time) {
    size_t lo=0,hi=meter->rampCount;
    while (lo<hi) { size_t mid=lo+(hi-lo)/2; if (meter->ramps[mid].start<=time) lo=mid+1; else hi=mid; }
    return lo ? lo-1 : 0;
}
static float rampGain(RenderMeterRef meter,double time,size_t *index) {
    if (!meter->rampCount || time<meter->ramps[0].start) return 1;
    while (*index+1<meter->rampCount && meter->ramps[*index+1].start<=time) ++*index;
    MeterRamp ramp=meter->ramps[*index];
    double fraction=fmax(0,fmin(1,(time-ramp.start)/(ramp.end-ramp.start)));
    return ramp.from+(ramp.to-ramp.from)*(float)fraction;
}
bool RenderMeterAppendEffects(RenderMeterRef meter,double start,double end,const RenderAudioEffectDescriptor *effects,size_t count,bool continuous) {
    if (!count) return true;
    if (!meter->program) meter->program=RenderAudioProgramCreate();
    return meter->program && RenderAudioProgramAppend(meter->program,start,end,effects,count,continuous);
}
bool RenderMeterProcessingFailed(RenderMeterRef meter) { return atomic_load_explicit(&meter->processingFailed,memory_order_relaxed); }
static void meterInit(MTAudioProcessingTapRef tap,void *client,void **storage) {
    RenderMeterRef meter = client;
    atomic_fetch_add_explicit(&meter->references,1,memory_order_relaxed); *storage = meter;
}
static void meterFinalize(MTAudioProcessingTapRef tap) { RenderMeterRelease(MTAudioProcessingTapGetStorage(tap)); }
static void meterPrepare(MTAudioProcessingTapRef tap,CMItemCount maxFrames,const AudioStreamBasicDescription *format) {
    RenderMeterRef meter = MTAudioProcessingTapGetStorage(tap); meter->format = *format;
    meter->supported = format->mSampleRate>0 && format->mFormatID == kAudioFormatLinearPCM && (format->mFormatFlags & kAudioFormatFlagIsFloat) && format->mBitsPerChannel == 32 && !(format->mFormatFlags & kAudioFormatFlagIsBigEndian);
    if (meter->program) {
        if (!meter->supported || format->mChannelsPerFrame>8) atomic_store_explicit(&meter->processingFailed,true,memory_order_relaxed);
        RenderAudioProgramPrepare(meter->program,format->mSampleRate);
    }
}
static void meterUnprepare(MTAudioProcessingTapRef tap) { ((RenderMeterRef)MTAudioProcessingTapGetStorage(tap))->supported = false; }
static void meterProcess(MTAudioProcessingTapRef tap,CMItemCount requested,MTAudioProcessingTapFlags flags,AudioBufferList *buffers,CMItemCount *framesOut,MTAudioProcessingTapFlags *flagsOut) {
    CMTimeRange range = kCMTimeRangeInvalid;
    *framesOut = 0;
    OSStatus status = MTAudioProcessingTapGetSourceAudio(tap,requested,buffers,flagsOut,&range,framesOut);
    RenderMeterRef meter = MTAudioProcessingTapGetStorage(tap);
    if (status != noErr || !meter->supported || *framesOut <= 0 || !CMTIMERANGE_IS_VALID(range)) return;
    double start = CMTimeGetSeconds(range.start), end = CMTimeGetSeconds(CMTimeRangeGetEnd(range));
    if (!isfinite(start) || !isfinite(end) || end <= start) return;
    if (meter->program) {
        float *pointers[8];unsigned strides[8],count=0;size_t safeFrames=(size_t)*framesOut;
        for (unsigned b=0;b<buffers->mNumberBuffers && count<8;b++) {
            AudioBuffer *buffer=&buffers->mBuffers[b];unsigned channels=buffer->mNumberChannels;
            if (!channels || !buffer->mData) continue;
            size_t available=buffer->mDataByteSize/sizeof(float)/channels;
            if (available<safeFrames) safeFrames=available;
            for (unsigned c=0;c<channels && count<8;c++,count++) { pointers[count]=(float *)buffer->mData+c;strides[count]=channels; }
        }
        RenderAudioProgramProcess(meter->program,pointers,strides,count,safeFrames,start,end-start);
    }
    if (!meter->slots) return;
    float peaks[8] = {0}, rms[8] = {0}; unsigned channel = 0;
    for (unsigned b=0;b<buffers->mNumberBuffers && channel<8;b++) {
        AudioBuffer *buffer = &buffers->mBuffers[b];
        unsigned channels = buffer->mNumberChannels;
        if (!channels || !buffer->mData) continue;
        size_t available = buffer->mDataByteSize / sizeof(float) / channels;
        size_t frames = (size_t)*framesOut < available ? (size_t)*framesOut : available;
        const float *samples = buffer->mData;
        for (unsigned c=0;c<channels && channel<8;c++,channel++) {
            double squareSum = 0; float peak = 0; size_t gainIndex = rampIndex(meter,start);
            for (size_t frame=0;frame<frames;frame++) {
                float value = samples[frame*channels+c] * rampGain(meter,start+(end-start)*(double)frame/(double)frames,&gainIndex);
                if (!isfinite(value)) continue;
                peak = fmaxf(peak,fabsf(value)); squareSum += (double)value*value;
            }
            peaks[channel] = peak; rms[channel] = frames ? (float)sqrt(squareSum/frames) : 0;
        }
    }
    MeterSlot *slot = &meter->slots[meter->writeIndex % RENDER_METER_SLOTS];
    unsigned long long sequence = 2 * (++meter->writeIndex);
    atomic_store_explicit(&slot->sequence,sequence-1,memory_order_seq_cst);
    atomic_store_explicit(&slot->start,doubleBits(start),memory_order_seq_cst); atomic_store_explicit(&slot->end,doubleBits(end),memory_order_seq_cst);
    atomic_store_explicit(&slot->channels,channel,memory_order_seq_cst);
    for (unsigned c=0;c<channel;c++) {
        atomic_store_explicit(&slot->peak[c],floatBits(peaks[c]),memory_order_seq_cst);
        atomic_store_explicit(&slot->rms[c],floatBits(rms[c]),memory_order_seq_cst);
    }
    atomic_store_explicit(&slot->sequence,sequence,memory_order_seq_cst);
}
MTAudioProcessingTapRef RenderMeterCreateTap(RenderMeterRef meter) {
    MTAudioProcessingTapCallbacks callbacks = {kMTAudioProcessingTapCallbacksVersion_0,meter,meterInit,meterFinalize,meterPrepare,meterUnprepare,meterProcess};
    MTAudioProcessingTapRef tap = NULL;
    if (MTAudioProcessingTapCreate(kCFAllocatorDefault,&callbacks,kMTAudioProcessingTapCreationFlag_PreEffects,&tap) != noErr) return NULL;
    return tap;
}
RenderMeterSnapshot RenderMeterRead(RenderMeterRef meter,double seconds) {
    RenderMeterSnapshot result = {0};
    if (!meter->slots || !isfinite(seconds)) return result;
    unsigned long long newest = 0;
    for (unsigned i=0;i<RENDER_METER_SLOTS;i++) {
        MeterSlot *slot = &meter->slots[i];
        unsigned long long first = atomic_load_explicit(&slot->sequence,memory_order_seq_cst);
        if (!first || (first&1)) continue;
        RenderMeterSnapshot value = {0};
        value.start = bitsDouble(atomic_load_explicit(&slot->start,memory_order_seq_cst));
        value.end = bitsDouble(atomic_load_explicit(&slot->end,memory_order_seq_cst));
        if (seconds < value.start || seconds >= value.end) continue;
        value.channels = atomic_load_explicit(&slot->channels,memory_order_seq_cst);
        if (value.channels>8) continue;
        for (unsigned c=0;c<value.channels;c++) {
            value.peak[c] = bitsFloat(atomic_load_explicit(&slot->peak[c],memory_order_seq_cst));
            value.rms[c] = bitsFloat(atomic_load_explicit(&slot->rms[c],memory_order_seq_cst));
        }
        unsigned long long last = atomic_load_explicit(&slot->sequence,memory_order_seq_cst);
        if (first == last && first > newest) { value.valid = true; result = value; newest = first; }
    }
    return result;
}
