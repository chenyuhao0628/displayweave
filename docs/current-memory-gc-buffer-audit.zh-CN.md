[English](current-memory-gc-buffer-audit.md) | [简体中文](current-memory-gc-buffer-audit.zh-CN.md)

# 当前内存、GC 与 Buffer 所有权审计

基线：`79cbf90`；真机 Profiling：**Pending**。

当前每帧路径：Transport `readExact` 分配一个外层 `byte[]`；Binary V2 Packet 用 Offset/Length 零拷贝视图；Legacy 复用同一数组但扫描 JSON/Annex-B 边界；NAL Summary 保存 Offset，只有配置 Codec 时复制 VPS/SPS/PPS；提交 Decoder 时复制到 MediaCodec Input Buffer；Swift 侧构造 Annex-B、Wire Header/Prefix 和四字节外层 Framing Data。

`allocatedFrameBytes`、`bufferReuseCount`、`bufferPoolMiss` 为发布窗口指标。ART GC Runtime 原为累计值却使用容易误解的字段名；现 `gcCount`/`gcTimeMs` 发布 Reset-safe 窗口增量，并有确定性 Delta 测试。

没有实现 FrameBufferPool。未来 Pool 必须用单一 Owner Token 覆盖 TCP Read→Latest Slot→Decoder Submission，在替换/拒绝/提交后归还，重连时按 Generation 失效，并禁止任何 Packet/NAL View 仍引用数组时归还。容量、最大保留尺寸、Oversize Bypass、Pool Miss 和 Use-after-return 断言必须先定义。
