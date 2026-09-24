# NVIDIA MCP89 (GeForce 320M) Nouveau HDMI Audio Fix

[English](#english) | [繁體中文](#繁體中文) | [简体中文](#简体中文)

---

<a name="english"></a>
## English

### Overview
This repository provides the complete Linux kernel patch set and precompiled modules to resolve the long-standing **silent HDMI audio issue** on NVIDIA MCP89 chipsets (GeForce 320M, found in Apple MacBookPro7,1, MacBook7,1, Macmini4,1, etc.) when running the open-source **Nouveau** DRM kernel driver connected to HDMI TVs/monitors via passive Mini-DisplayPort to HDMI adapters.

### Problem Description
Under Linux (kernel 5.x / 6.x), the MCP89 GeForce 320M GPU detects the external HDMI display, and the ALSA HDA audio controller (`00:08.0`, Codec#4 `Nvidia MCP89 HDMI`) successfully identifies the display's ELD (e.g. `TEAC TV`). Audio players (`aplay`, `pipewire`, `wireplumber`) appear to play without errors and DMA pointers advance, but **no audible sound is emitted from the TV speakers**. The same hardware setup functions flawlessly under macOS.

### Root Cause Analysis & Hardware Reverse Engineering
Through Envytools register reverse engineering and live physical MMIO hardware diffing (`0x61c000 - 0x61d000`), four critical hardware-level faults were discovered in upstream Nouveau (`drivers/gpu/drm/nouveau`):

1. **ACR (Audio Clock Regeneration) Packet Transmission Disabled**:
   In `drivers/gpu/drm/nouveau/nvkm/engine/disp/gt215.c`, the upstream driver explicitly masked out bit 0:
   ```c
   nvkm_mask(device, 0x61c568 + soff, 0x00010101, 0x00000000); /* ACR_CTRL */
   ```
   Bit 0 of `ACR.CTRL` (`0x61c568 + soff`) is the master enable bit for ACR packet transmission. Disabling it stops all ACR packets, preventing the TV's HDMI audio PLL from locking to the pixel clock.
2. **Missing CTS (Cycle Time Stamp) Tables**:
   Upstream Nouveau only wrote N-values to `0x61c570/78/80`, leaving all CTS registers (`0x61c56c/74/7c`) at `0`. Without valid CTS values, the sink device cannot regenerate the audio master clock (MCLK).
3. **Audio InfoFrame Checksum / Payload Mismatch**:
   Upstream Nouveau wrote a mock dummy byte `0x00000071` to `INFOFRAME_PB`. This is replaced with a compliant CEA-861 2-channel LPCM InfoFrame (`0x00000201` header, `0x00000170` payload).
4. **DisplayPort vs HDMI TMDS Protocol Conflict**:
   In `dispnv50/disp.c`, when a passive adapter is connected, the encoder type is `DCB_OUTPUT_DP` but the sink monitor is HDMI. The driver now forces HDMI TMDS audio framing and explicitly mutes DP audio (`0x61c1e0 + soff`) to eliminate protocol collisions.

### Repository Contents
- `patches/nouveau-mcp89-hdmi-audio-all-in-one.patch`: Consolidated kernel source patch against Linux 6.6 LTS.
- `packages/nouveau.ko`: Precompiled patched Nouveau kernel module for `6.6.119-antix.1-amd64-smp`.
- `packages/vmlinuz-*` & `packages/initrd.img-*`: Full precompiled kernel and matching initramfs.
- `scripts/install_module.sh`: Automated installer script for the kernel module and initramfs update.
- `scripts/test_hdmi_audio.sh`: Quick ALSA unmute and 48kHz/44.1kHz audio playback test.
- `scripts/dump_hdmi_regs.py`: Python diagnostic tool to dump SOR1 MMIO HDMI audio registers via `/dev/mem`.
- `SHA256SUMS`: Cryptographic verification hashes for all files.

### Quick Start (Precompiled Module)
```bash
git clone https://github.com/obhasashare2024-namo/nouveau-mcp89-hdmi-audio.git
cd nouveau-mcp89-hdmi-audio

# 1. Install patched module
sudo bash scripts/install_module.sh

# 2. Ensure your GRUB command line contains:
#    nouveau.modeset=1 nouveau.config=NvAudio=1

# 3. Reboot and verify audio
sudo reboot

# After reboot:
bash scripts/test_hdmi_audio.sh
```

### ⚠️ Operational Pitfalls & Troubleshooting Guide
1. **Display Resolution & Pixel Clock Coupling Trap**:
   - The programmed hardware CTS table requires **1080p@60Hz (Pixel Clock = 148.5 MHz)**. If the window manager or display configuration silently falls back to mirroring your laptop screen at `1280x800` (~71 MHz), the TMDS clock will mismatch CTS, causing the TV's HDMI PLL to lose lock and mute.
   - Always lock your external display resolution:
     ```bash
     xrandr --output DP-1 --mode 1920x1080 --rate 60.00
     ```
2. **ALSA IEC958 Mixer Mute Gate**:
   - After reboot, ALSA digital S/PDIF channels may initialize in a muted state. Make sure `numid=37` (`IEC958 Playback Switch, index 1`, targeting TEAC TV Device 7) is unmuted:
     ```bash
     amixer -c 0 cset numid=37 on
     ```
3. **PipeWire Resource Contention (`EBUSY`)**:
   - When web browsers (e.g. Thorium/Chromium) play media, PipeWire locks `/dev/snd/pcmC0D7p`. Direct ALSA calls (`aplay -D plughw:0,7`) will fail with `Device or resource busy`. Route audio through `default` (`speaker-test -D default`) or close the browser before testing raw ALSA.
4. **Locking PipeWire Clock Rate to 48kHz**:
   - To prevent TV PLL relock glitches during dynamic 44.1k/48k sample rate switching, lock PipeWire to 48kHz:
     Add to `~/.config/pipewire/pipewire.conf.d/10-clock.conf`:
     ```spa
     context.properties = {
         default.clock.rate = 48000
         default.clock.allowed-rates = [ 48000 ]
     }
     ```
5. **TV DAC Standby Auto-Mute**:
   - Modern HDMI TVs put their internal audio DAC into sleep mode after a few minutes of silence. A <0.5s sound may be clipped during DAC wake-up. Use a continuous 1-second sine wave or speech prompt to wake the sink.

---

<a name="繁體中文"></a>
## 繁體中文

### 專案概述
本版本庫提供完整 Linux 內核補丁與預編譯模組，徹底解決 NVIDIA MCP89 晶片組（GeForce 320M，搭載於 Apple MacBookPro7,1、MacBook7,1、Macmini4,1 等老款蘋果機）在開源 **Nouveau** 驅動下，透過被動式 Mini-DisplayPort 轉接 HDMI 連接電視/螢幕時**長期無聲**的硬件底層缺陷。

### 問題背景
在 Linux 5.x / 6.x 內核中，MCP89 GeForce 320M 能正常點亮電視畫面，ALSA HDA 音訊控制器（`00:08.0`，Codec#4）亦能正確讀取電視 ELD（如 `TEAC TV`）。播放器（`aplay`、`pw-play`、`pipewire`）執行時進度正常且 DMA 指標流暢推進，但**電視端完全靜音**。同一組線材與轉接頭在 macOS 下能正常發聲，證明硬件本身無故障。

### 硬件逆向與根本原因（Root Cause）
結合 Envytools 暫存器逆向與真機 MMIO 運行時差分（`0x61c000 - 0x61d000`），定位出官方 Nouveau 驅動的四大硬傷：

1. **ACR（音訊時脈再生）封包發送被強制關閉**：
   在 `drivers/gpu/drm/nouveau/nvkm/engine/disp/gt215.c` 中，原驅動寫入：
   ```c
   nvkm_mask(device, 0x61c568 + soff, 0x00010101, 0x00000000); /* ACR_CTRL */
   ```
   其中 `ACR.CTRL`（`0x61c568 + soff`）的第 0 位元即為 ACR 發送總開關！原代碼將其清零，導致電視端的 HDMI 音訊鎖相環（PLL）無法鎖定像素時脈，電視硬體 DAC 進入靜音保護。
2. **缺失 CTS（週期時間戳）對照表**：
   原驅動僅向 `0x61c570/78/80` 寫入 N 值，CTS 暫存器（`0x61c56c/74/7c`）全數為 0。補丁補齊了 32kHz、44.1kHz、48kHz 等全取樣率的標準 CTS 表。
3. **Audio InfoFrame 格式與校驗碼錯誤**：
   原代碼僅向 `INFOFRAME_PB` 寫入偽造數據 `0x00000071`。補丁修正為標準 CEA-861 2 聲道 LPCM 規範（`0x00000201` 檔頭，`0x00000170` 負載）。
4. **DisplayPort 與 HDMI TMDS 協議衝突消除**：
   在 `dispnv50/disp.c` 中，當被動轉接頭被辨識為 DP 輸出但 Sink 是 HDMI 時，強制啟用 HDMI TMDS 音訊鏈路，並同步關閉 DP_AUDIO（`0x61c1e0 + soff`），防止協議互斥。

### 快速安裝（預編譯模組）
```bash
git clone https://github.com/obhasashare2024-namo/nouveau-mcp89-hdmi-audio.git
cd nouveau-mcp89-hdmi-audio

# 1. 執行一鍵模組安裝
sudo bash scripts/install_module.sh

# 2. 確認 GRUB 開機參數包含：
#    nouveau.modeset=1 nouveau.config=NvAudio=1

# 3. 重啟系統並測試出聲
sudo reboot

# 重啟完成後執行驗證：
bash scripts/test_hdmi_audio.sh
```

### 🚨 運維實戰與避坑指南 (Pitfall Avoidance)
1. **顯示解析度與時脈失配陷阱（最高頻坑點）**：
   - 硬體中的 CTS 時脈表精確依賴 **1080p@60Hz (像素時脈 148.5 MHz)**。若桌面環境在重啟或休眠喚醒時，將 `DP-1` 偷偷切回與筆電內建螢幕鏡像的 `1280x800`（像素時脈約 71 MHz），電視 HDMI PLL 會因時脈失配直接靜音。
   - 解決方法：開機後或切換顯示時，強制鎖定 1080p：
     ```bash
     DISPLAY=:0 xrandr --output DP-1 --mode 1920x1080 --rate 60.00
     ```
2. **ALSA IEC958 混音器靜音閘門**：
   - 開機後若電視無聲，首先檢查 S/PDIF 混音器開關。對應電視 Device 7 的核心開關為 `numid=37`，必須確認為 `on`：
     ```bash
     amixer -c 0 cset numid=37 on
     ```
3. **PipeWire / 瀏覽器資源獨佔（EBUSY 報錯）**：
   - 當 Thorium/Chromium 打開 YouTube 時，後台 `AudioService` 會透過 PipeWire 獨佔 `/dev/snd/pcmC0D7p`。此時若在終端直連硬體（`aplay -D plughw:0,7`）會報 `裝置或系統資源忙碌中`。測試直連前應先關閉瀏覽器，或統一透過系統混音 `default` 輸出。
4. **鎖定 PipeWire 取樣率為 48kHz 防止脫鎖**：
   - YouTube 串流通常為 44.1kHz，頻繁切換取樣率容易導致老款電視 PLL 抖動脫鎖。建議鎖死 PipeWire 採樣率為 48000Hz（讓 PipeWire 高品質重採樣），保持 HDMI TMDS 時鐘恆定。
5. **電視 DAC 節能自動休眠 (Auto-Mute)**：
   - 電視在幾分鐘無音訊輸入時會進入 DAC 節能，播放極短音訊（<0.5 秒）開頭可能被吃掉。建議使用 1 秒以上的持續正弦波或語音來喚醒 DAC。

---

<a name="简体中文"></a>
## 简体中文

### 项目概述
本代码库提供完整的 Linux 内核补丁与预编译模块，彻底修复 NVIDIA MCP89 芯片组（GeForce 320M，广泛用于 Apple MacBookPro7,1、MacBook7,1、Macmini4,1 等机型）在开源 **Nouveau** 驱动下，通过 Mini-DP 转 HDMI 被动线连接电视/显示器时**长期静音**的历史遗留问题。

### 问题根因与底层逆向
经由 Envytools 寄存器逆向及真机 MMIO 差异分析，查明 Nouveau 驱动存在以下关键缺陷：
1. **ACR 时钟再生传输被清零**：`gt215.c` 中显式清除 `ACR.CTRL`（`0x61c568 + soff`）的第 0 位，导致 ACR 数据包未发送，电视 HDMI 音频 PLL 无法锁定。
2. **缺失 CTS 对照表**：未写入 CTS 时钟周期值，导致电视端无法还原音频主时钟。
3. **Audio InfoFrame 错误**：原伪造校验和导致部分电视直接丢弃音频流。
4. **DP/TMDS 协议混淆**：被动转接下缺少向 TMDS HDMI 模式的切换与 DP_AUDIO 互锁。

### 🚨 避坑指南与实战运维
1. **分辨率时钟失配**：外接电视必须工作在 `1920x1080@60Hz`（148.5MHz），若回落至 `1280x800` 镜像模式会导致时钟脱节无声。
2. **ALSA IEC958 静音开关**：确认 `amixer -c 0 cset numid=37 on` 已开启。
3. **PipeWire 独占与采样率漂移**：浏览器播放时独占声卡会导致直连报错 `EBUSY`；建议将 PipeWire 默认时钟锁定为 48000Hz 保证时钟稳定。
4. **电视 DAC 节能休眠**：长时间无声音输入时电视 DAC 会休眠，建议使用至少 1 秒以上的音频激活。

### 许可证
本补丁遵循 Linux 内核原生 GPLv2 许可证。
