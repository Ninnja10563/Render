#include "AudioEffects.h"
#include <assert.h>
#include <math.h>
#include <stdio.h>
#include <stdlib.h>
static double run(unsigned kind,double gain) {
 const unsigned count=96000;float *samples=malloc(count*sizeof(float));
 for(unsigned i=0;i<count;i++)samples[i]=0.4*sin(2*3.141592653589793*1000*i/48000);
 RenderAudioEffectDescriptor fx={0};fx.kind=kind;
 if(kind==0){fx.values[0]=0;fx.values[1]=gain;fx.values[2]=0;fx.values[3]=120;fx.values[4]=1000;fx.values[5]=6000;fx.values[6]=1;}
 if(kind==1){fx.values[0]=-24;fx.values[1]=4;fx.values[2]=1;fx.values[3]=100;fx.values[4]=0;}
 if(kind==2){fx.values[0]=-12;fx.values[1]=50;}
 if(kind==3){fx.values[0]=-3;fx.values[1]=-60;fx.values[2]=5;fx.values[3]=20;}
 RenderAudioProgramRef p=RenderAudioProgramCreate();assert(p);assert(RenderAudioProgramAppend(p,0,2,&fx,1,false));RenderAudioProgramPrepare(p,48000);
 unsigned stride=1;RenderAudioProgramProcess(p,&samples,&stride,1,count,0,2);double peak=0;
 for(unsigned i=count/2;i<count;i++){assert(isfinite(samples[i]));peak=fmax(peak,fabs(samples[i]));}
 RenderAudioProgramDestroy(p);free(samples);return peak;
}
static RenderAudioProgramRef limiterProgram(double start,double end) {
 RenderAudioEffectDescriptor fx={0};fx.kind=2;fx.values[0]=-12;fx.values[1]=50;
 RenderAudioProgramRef p=RenderAudioProgramCreate();assert(p);assert(RenderAudioProgramAppend(p,start,end,&fx,1,false));RenderAudioProgramPrepare(p,48000);return p;
}
static void checkChunksAndSeek(void) {
 const unsigned count=48000;float *whole=malloc(count*2*sizeof(float)),*chunked=malloc(count*2*sizeof(float));assert(whole&&chunked);
 for(unsigned i=0;i<count;i++){whole[2*i]=0.7*sin(2*3.141592653589793*997*i/48000);whole[2*i+1]=whole[2*i]*0.25;}
 for(unsigned i=0;i<count*2;i++)chunked[i]=whole[i];
 RenderAudioProgramRef a=limiterProgram(0,1),b=limiterProgram(0,1);float *channels[]={whole,whole+1};unsigned strides[]={2,2};
 RenderAudioProgramProcess(a,channels,strides,2,count,0,1);
 for(unsigned offset=0;offset<count;){unsigned frames=137;if(offset+frames>count)frames=count-offset;float *part[]={chunked+2*offset,chunked+2*offset+1};RenderAudioProgramProcess(b,part,strides,2,frames,offset/48000.0,frames/48000.0);offset+=frames;}
 for(unsigned i=0;i<count*2;i++){assert(fabs(whole[i]-chunked[i])<1e-7);assert(fabs(whole[i])<=pow(10,-.6)+1e-6);}
 for(unsigned i=0;i<count;i++)assert(fabs(whole[2*i+1]-whole[2*i]*.25)<1e-7);
 float seek[256],fresh[256];for(unsigned i=0;i<256;i++)seek[i]=fresh[i]=0.1;
 RenderAudioProgramRef c=limiterProgram(0,1);float *x=seek,*y=fresh;unsigned stride=1;
 RenderAudioProgramProcess(b,&x,&stride,1,256,.25,256/48000.0);RenderAudioProgramProcess(c,&y,&stride,1,256,.25,256/48000.0);
 for(unsigned i=0;i<256;i++)assert(fabs(seek[i]-fresh[i])<1e-7);
 RenderAudioProgramDestroy(a);RenderAudioProgramDestroy(b);RenderAudioProgramDestroy(c);free(whole);free(chunked);
}
static void checkWindowAndValidation(void) {
 RenderAudioProgramRef p=limiterProgram(.25,.75);float samples[48000];for(unsigned i=0;i<48000;i++)samples[i]=.5;
 float *channel=samples;unsigned stride=1;RenderAudioProgramProcess(p,&channel,&stride,1,48000,0,1);
 for(unsigned i=0;i<48000;i++)assert(fabs(samples[i]-((i>=12000&&i<36000)?pow(10,-.6):.5))<1e-6);
 RenderAudioEffectDescriptor fx={0};fx.kind=99;assert(!RenderAudioProgramAppend(p,1,2,&fx,1,false));fx.kind=0;fx.values[0]=NAN;assert(!RenderAudioProgramAppend(p,1,2,&fx,1,false));
 assert(!RenderAudioProgramAppend(p,.5,1,NULL,0,false));RenderAudioProgramDestroy(p);
}
static void checkContinuousSplit(void) {
 RenderAudioEffectDescriptor fx={0};fx.kind=1;fx.values[0]=-24;fx.values[1]=4;fx.values[2]=10;fx.values[3]=100;fx.values[4]=6;
 RenderAudioProgramRef a=RenderAudioProgramCreate(),b=RenderAudioProgramCreate();assert(a&&b);
 assert(RenderAudioProgramAppend(a,0,1,&fx,1,false));assert(RenderAudioProgramAppend(b,0,.5,&fx,1,false));assert(RenderAudioProgramAppend(b,.5,1,&fx,1,true));
 RenderAudioProgramPrepare(a,48000);RenderAudioProgramPrepare(b,48000);
 float x[48000],y[48000];for(unsigned i=0;i<48000;i++)x[i]=y[i]=.4*sin(2*3.141592653589793*440*i/48000);
 float *px=x,*py=y;unsigned stride=1;RenderAudioProgramProcess(a,&px,&stride,1,48000,0,1);RenderAudioProgramProcess(b,&py,&stride,1,48000,0,1);
 for(unsigned i=0;i<48000;i++)assert(fabs(x[i]-y[i])<1e-7);
 RenderAudioProgramDestroy(a);RenderAudioProgramDestroy(b);
}
int main(void){checkContinuousSplit();checkChunksAndSeek();checkWindowAndValidation();double neutral=run(0,0),boost=run(0,6),compress=run(1,0),limit=run(2,0),gate=run(3,0);printf("neutral %.6f boost %.6f compressor %.6f limiter %.6f gate %.6f\n",neutral,boost,compress,limit,gate);assert(fabs(neutral-.4)<1e-6);assert(fabs(boost-.4*pow(10,.3))<1e-4);assert(compress<.2&&compress>.05);assert(limit<=pow(10,-.6)+1e-6);assert(gate<.001);}
