# Audio processing

AudioEffect descriptors belong to ClipProperties and use the same validated project commands, serialization, and undo snapshots as other clip properties. Each enabled stack compiles into a bounded C program attached to its reusable AVComposition audio input through MTAudioProcessingTap. Disjoint timeline segments select the appropriate source stack. The callback allocates no memory, performs no I/O, and calls no Swift or UI code.

Three-band EQ uses low/high shelves and a parametric middle band, with coefficients derived from the [Audio EQ Cookbook](https://webaudio.github.io/Audio-EQ-Cookbook/audio-eq-cookbook.html). Coefficients are calculated before processing. The compressor uses a linked peak detector, attack/release envelope, soft knee, ratio, and makeup gain. The sample peak limiter applies immediate linked gain reduction with a release envelope. The noise gate uses a decaying peak detector and separate opening/closing time constants. Interleaved and planar Float32 audio support up to eight channels.

Processing precedes AVAudioMix volume automation. The optional meter measures processed samples multiplied by the compiled fader envelope. The same program is attached for preview, reader/writer exports, and preset exports. Unsupported processing formats cause an explicit error; no completed export file is published on that error.

A compound's nonlinear bus effect cannot be distributed independently over its children without changing its sound. This version therefore validates against audio effects on compound instances. A future bus engine must process each complete child sum once, both live and offline. Static clip processor parameters do not yet support automation. The existing volume keyframes remain available.

Run `scripts/test-audio-dsp.sh` for numerical C tests. macOS runs AddressSanitizer and UndefinedBehaviorSanitizer; Linux runs UBSan because this development container cannot reserve ASan's address space. Native integration tests decode actual samples and compare H.264, HEVC, ProRes, and bitrate-controlled exports. Physical-device latency/CPU profiling and subjective listening remain release qualification work.
