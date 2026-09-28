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
struct RenderMeter {
    atomic_uint references;
    unsigned writeIndex;
    bool supported;
    AudioStreamBasicDescription format;
    MeterSlot slots[RENDER_METER_SLOTS];
};
static unsigned floatBits(float value) { unsigned bits; memcpy(&bits,&value,sizeof(bits)); return bits; }
static float bitsFloat(unsigned bits) { float value; memcpy(&value,&bits,sizeof(value)); return value; }
static unsigned long long doubleBits(double value) { unsigned long long bits; memcpy(&bits,&value,sizeof(bits)); return bits; }
static double bitsDouble(unsigned long long bits) { double value; memcpy(&value,&bits,sizeof(value)); return value; }
RenderMeterRef RenderMeterCreate(void) {
    RenderMeterRef meter = calloc(1,sizeof(struct RenderMeter));
    if (!meter) return NULL;
    atomic_init(&meter->references,1);
    for (unsigned i=0;i<RENDER_METER_SLOTS;i++) {
        MeterSlot *slot = &meter->slots[i];
        atomic_init(&slot->sequence,0); atomic_init(&slot->start,0); atomic_init(&slot->end,0); atomic_init(&slot->channels,0);
        for (unsigned c=0;c<8;c++) { atomic_init(&slot->peak[c],0); atomic_init(&slot->rms[c],0); }
    }
    return meter;
}
void RenderMeterRelease(RenderMeterRef meter) {
    if (atomic_fetch_sub_explicit(&meter->references,1,memory_order_acq_rel)==1) free(meter);
}
static void meterInit(MTAudioProcessingTapRef tap,void *client,void **storage) {
    RenderMeterRef meter = client;
    atomic_fetch_add_explicit(&meter->references,1,memory_order_relaxed); *storage = meter;
}
static void meterFinalize(MTAudioProcessingTapRef tap) { RenderMeterRelease(MTAudioProcessingTapGetStorage(tap)); }
static void meterPrepare(MTAudioProcessingTapRef tap,CMItemCount maxFrames,const AudioStreamBasicDescription *format) {
    RenderMeterRef meter = MTAudioProcessingTapGetStorage(tap); meter->format = *format;
    meter->supported = format->mFormatID == kAudioFormatLinearPCM && (format->mFormatFlags & kAudioFormatFlagIsFloat) && format->mBitsPerChannel == 32 && !(format->mFormatFlags & kAudioFormatFlagIsBigEndian);
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
    float peaks[8] = {0}, rms[8] = {0}; unsigned channel = 0;
    for (unsigned b=0;b<buffers->mNumberBuffers && channel<8;b++) {
        AudioBuffer *buffer = &buffers->mBuffers[b];
        unsigned channels = buffer->mNumberChannels;
        if (!channels || !buffer->mData) continue;
        size_t available = buffer->mDataByteSize / sizeof(float) / channels;
        size_t frames = (size_t)*framesOut < available ? (size_t)*framesOut : available;
        const float *samples = buffer->mData;
        for (unsigned c=0;c<channels && channel<8;c++,channel++) {
            double squareSum = 0; float peak = 0;
            for (size_t frame=0;frame<frames;frame++) {
                float value = samples[frame*channels+c];
                if (!isfinite(value)) continue;
                peak = fmaxf(peak,fabsf(value)); squareSum += (double)value*value;
            }
            peaks[channel] = peak; rms[channel] = frames ? (float)sqrt(squareSum/frames) : 0;
        }
    }
    MeterSlot *slot = &meter->slots[meter->writeIndex++ % RENDER_METER_SLOTS];
    unsigned long long sequence = atomic_load_explicit(&slot->sequence,memory_order_relaxed);
    atomic_store_explicit(&slot->sequence,sequence+1,memory_order_seq_cst);
    atomic_store_explicit(&slot->start,doubleBits(start),memory_order_seq_cst); atomic_store_explicit(&slot->end,doubleBits(end),memory_order_seq_cst);
    atomic_store_explicit(&slot->channels,channel,memory_order_seq_cst);
    for (unsigned c=0;c<channel;c++) {
        atomic_store_explicit(&slot->peak[c],floatBits(peaks[c]),memory_order_seq_cst);
        atomic_store_explicit(&slot->rms[c],floatBits(rms[c]),memory_order_seq_cst);
    }
    atomic_store_explicit(&slot->sequence,sequence+2,memory_order_seq_cst);
}
MTAudioProcessingTapRef RenderMeterCreateTap(RenderMeterRef meter) {
    MTAudioProcessingTapCallbacks callbacks = {kMTAudioProcessingTapCallbacksVersion_0,meter,meterInit,meterFinalize,meterPrepare,meterUnprepare,meterProcess};
    MTAudioProcessingTapRef tap = NULL;
    if (MTAudioProcessingTapCreate(kCFAllocatorDefault,&callbacks,kMTAudioProcessingTapCreationFlag_PostEffects,&tap) != noErr) return NULL;
    return tap;
}
RenderMeterSnapshot RenderMeterRead(RenderMeterRef meter,double seconds) {
    RenderMeterSnapshot result = {0};
    if (!isfinite(seconds)) return result;
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
        if (first == last) { value.valid = true; result = value; }
    }
    return result;
}
