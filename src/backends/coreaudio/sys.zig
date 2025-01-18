//! Re-exports the C headers needed to interface with the CoreAudio API.

pub usingnamespace @cImport({
    @cInclude("CoreAudio/CoreAudio.h");
    @cInclude("AudioUnit/AUComponent.h");
    @cInclude("audioUnit/AudioUnitProperties.h");
    @cInclude("AudioUnit/AudioUnit.h");
    @cInclude("AudioToolbox/AudioFormat.h");
    @cInclude("mach/mach_time.h");
});
