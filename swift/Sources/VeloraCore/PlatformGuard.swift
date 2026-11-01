//
//  PlatformGuard.swift
//  VeloraCore
//
//  Compile-time platform guard to strictly enforce Apple Silicon (ARM64) macOS devices.
//

#if !arch(arm64)
#error("VeloraCore is designed exclusively for Apple Silicon (ARM64) macOS devices running macOS 15 (Sequoia) or later.")
#endif
