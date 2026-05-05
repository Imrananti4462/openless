//! 本地 ASR 引擎入口。
//!
//! 当前只在 macOS 编入 antirez/qwen-asr (纯 C + Accelerate)；Windows 端
//! 的本地推理路径见 issue #256，本期不实现。

#[cfg(target_os = "macos")]
mod qwen_engine;
#[cfg(target_os = "macos")]
mod qwen_ffi;

#[cfg(target_os = "macos")]
pub use qwen_engine::QwenAsrEngine;
