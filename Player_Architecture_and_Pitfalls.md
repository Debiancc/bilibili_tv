# Bilibili TV 播放器架构演进与避坑指南 (AVPlayer DASH 踩坑实录)

本文档旨在记录并解释我们在 Bilibili TV 项目中，为了在 Apple TV 上使用原生 `AVPlayer` 播放 B 站的高清 DASH (M4S) 视频流，所经历的架构演进、踩过的深坑，以及最终的极简优雅解决方案。

## 1. 业务背景与技术挑战

B 站的高清视频（如 1080P、4K、HDR）均采用 DASH (Dynamic Adaptive Streaming over HTTP) 协议下发，音视频轨道是分离的单独文件 (`.m4s` 格式)。

由于 Apple 生态系统内的原生 `AVPlayer` **不支持原生解析 DASH**，仅支持 HLS (M3U8) 和 MP4，若想使用原生的 `AVPlayerViewController` 以获得最完美的 tvOS 交互体验（包括原生的画中画、Siri 进度控制、空间音频、HDR 支持），我们必须要在本地做一层 **DASH 到 HLS 的协议转换代理 (Proxy)**。

## 2. 第一阶段：过度设计的深坑 (The `-12860` Pitfall)

最初，我们的思路是“全面代理控制”，以解决 B 站的防盗链（需要携带 `Referer` 和 `User-Agent` HTTP Headers）。

### 我们早期的架构：
1. **本地 M3U8 生成器**：在本地启动一个自定义的 Schema (如 `bili-hls://`) 协议拦截。
2. **切片数据拦截**：利用 `AVAssetResourceLoaderDelegate` 拦截对 M3U8 和所有切片 (Segment `.m4s`) 的请求。
3. **内存数据喂养**：在 `ResourceLoader` 中使用我们自己的 `URLSession` 向 B 站服务器发起携带防盗链 Header 的 `Range` 请求，将下载到的数据分块塞回给 `AVPlayer` (`loadingRequest.dataRequest?.respond(with: data)`)。

### 遭遇的致命报错：`err=-12860`
这套逻辑在测试时，`AVPlayer` (底层的 `FigStreamPlayer`) 抛出了致命错误：
`err=-12860 (kFigStreamPlayerError_SegmentFormatNotRecognized)`

### 根本原因排查与深度剖析：
经过对比 ISO BMFF 标准与 Apple HLS 规范，我们发现了深层次原因：
1. **B 站的 fMP4 切片设计**：B 站的 `.m4s` 切片内部的 `moof`（Movie Fragment）使用了**绝对偏移量** (`base_data_offset`)。
2. **Apple CMAF 解析器的严苛要求**：Apple 官方的 HLS CMAF 标准，严格要求 HLS 切片中的 `moof` 必须使用**相对偏移量**（即设置 `default-base-is-moof` 标志位）。
3. **ResourceLoader 的代理冲突**：当我们将带有“绝对偏移量”的非标 fMP4 切片通过 `AVAssetResourceLoaderDelegate` 这种**非标准 HTTP (内存数据流)** 的方式喂给 `AVPlayer` 时，Apple 底层严格的 CMAF Parser 会试图对字节流进行重新索引和校验，由于偏移量不符且丧失了原生 HTTP Range 语境，导致解析器直接崩溃，拒绝播放。

为了解决这个问题，我们甚至尝试了手动去解析和合并 `sidx` (Segment Index Box)，甚至计算切片的 ByteRange，但只要切片是通过 `ResourceLoaderDelegate` 塞进去的，统统以 `-12860` 告终。

## 3. 第二阶段：顿悟与降维打击 (The Native Network Bypass)

在查阅并分析了开源社区的实现（如 `ATV-Bilibili-demo`）后，我们找到了一个令人惊叹的极简解法。

核心破局点在于：**如果我们能让 `AVPlayer` 直接使用原生的 HTTP 网络栈去下载切片，底层原生的 CFNetwork 能够完美兼容这种带有绝对偏移量的 fMP4 文件！**

但是，原生的网络栈怎么加上防盗链 Header 呢？
答案是 `AVURLAssetHTTPHeaderFieldsKey`！

### 最终的优雅架构：
1. **全局 Header 注入**：我们在创建 `AVURLAsset` 时，通过 `options` 直接将防盗链 Header 注入。
   ```swift
   let options: [String: Any] = ["AVURLAssetHTTPHeaderFieldsKey": headers]
   let asset = AVURLAsset(url: masterURL, options: options)
   ```
   *这一步非常神奇，它告诉 AVPlayer，不仅是最初的请求，连后续 M3U8 里解析出的所有子请求，都要自动带上这些 Header。*

2. **精简的 ResourceLoader (仅拦截 M3U8)**：
   我们保留 `AVAssetResourceLoaderDelegate`，但**仅仅**用来拦截 `bili-hls://` 生成本地的 M3U8 清单。

3. **M3U8 中的“真身”**：
   在生成的 `video.m3u8` 和 `audio.m3u8` 中，我们**直接写入 B 站服务器真实的 `https://...` CDN 链接**，而不是经过我们代理的链接。
   ```m3u8
   #EXTM3U
   #EXT-X-VERSION:7
   #EXT-X-MAP:URI="https://upos-sz-mirror...m4s",BYTERANGE="933@0"
   #EXTINF:5.0,
   #EXT-X-BYTERANGE:3581089@18049
   https://upos-sz-mirror...m4s
   ```

### 为什么这样就通了？
当 `AVPlayer` 解析这个 M3U8 时，它发现切片的 URI 是 `https://...`，它会自动**跳过**我们的 `ResourceLoader`，直接使用原生的底层 HTTP 栈发起请求。
它自动带上了我们在 `AVURLAsset` 传入的 Header，自动处理了 HTTP `Range`，并且原生网络栈内部以文件 IO 形式处理了 B 站魔改的 fMP4 绝对偏移量，彻底绕开了 CMAF Parser 针对代理内存流的严苛检查。

## 4. 总结与清理

通过这次架构调整，我们移除了大量的冗余代码：
*   **移除了**：用来代理下载切片的 `URLSession` 和繁琐的 `URLSessionDataDelegate`。
*   **移除了**：手动模拟 `contentLength` 和伪造文件结尾的玄学规避代码。
*   **移除了**：大量的并发与内存争用逻辑。

现在的 Bilibili TV 播放器不仅支持了原生 tvOS 播放器的所有高级特性，而且因为切片下载回交给了 iOS/tvOS 最底层的原生网络栈，播放的起播速度、内存占用、缓冲稳定性和续航都达到了最佳的系统级表现。
