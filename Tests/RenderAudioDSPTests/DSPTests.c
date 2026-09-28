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
 RenderAudioProgramRef p=RenderAudioProgramCreate();assert(p);assert(RenderAudioProgramAppend(p,0,2,&fx,1));RenderAudioProgramPrepare(p,48000);
 unsigned stride=1;RenderAudioProgramProcess(p,&samples,&stride,1,count,0,2);double peak=0;
 for(unsigned i=count/2;i<count;i++){assert(isfinite(samples[i]));peak=fmax(peak,fabs(samples[i]));}
 RenderAudioProgramDestroy(p);free(samples);return peak;
}
int main(void){double neutral=run(0,0),boost=run(0,6),compress=run(1,0),limit=run(2,0),gate=run(3,0);printf("neutral %.6f boost %.6f compressor %.6f limiter %.6f gate %.6f\n",neutral,boost,compress,limit,gate);assert(fabs(neutral-.4)<1e-6);assert(fabs(boost-.4*pow(10,.3))<1e-4);assert(compress<.2&&compress>.05);assert(limit<=pow(10,-.6)+1e-6);assert(gate<.001);}
