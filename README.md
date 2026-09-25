# NVIDIA MCP89 (GeForce 320M) Nouveau HDMI Audio Fix & MacBookPro7,1 Ecosystem Suite

[English](#english) | [繁體中文](#繁體中文) | [简体中文](#简体中文)

---

<a name="english"></a>
## English

### Overview
This repository provides the complete Linux kernel patch set, precompiled modules, and ecosystem scripts to resolve the long-standing **silent HDMI audio issue**, **TV overscan/underscan**, **standby display lockups**, **RTC time freeze**, and **browser video stutter** on NVIDIA MCP89 chipsets (GeForce 320M / MacBookPro7,1, MacBook7,1, Macmini4,1) running the open-source **Nouveau** DRM driver on modern Linux (antiX, Debian, Ubuntu).

### 1. Kernel-Level HDMI Audio Reverse Engineering & Fix
Through Envytools register reverse engineering and live physical MMIO hardware diffing (`0x61c000 - 0x61d000`), four critical hardware-level faults were discovered and fixed in upstream Nouveau (`drivers/gpu/drm/nouveau/nvkm/engine/disp/gt215.c`):

1. **ACR (Audio Clock Regeneration) Packet Transmission Enabled**:
   Bit 0 of `ACR.CTRL` (`0x61c568 + soff`) was cleared by upstream code (`0x00010101 -> 0x00000000`). Restoring bit 0 enables ACR transmission, allowing the sink TV's PLL to lock onto the HDMI pixel clock.
2. **CTS (Cycle Time Stamp) & N-Value Programming**:
   Programmed compliant CTS values (e.g. `148500 << 8` for 1080p60 148.5MHz dotclock) and matching N-registers (`0x61c570/78/80`, `N=6144` for 48kHz, `N=5644` for 44.1kHz).
3. **Audio InfoFrame Checksum / Payload Mismatch**:
   Replaced dummy mock bytes with standard CEA-861 2-channel LPCM InfoFrame headers (`0x00000201`) and payload (`0x00000170`).
4. **DisplayPort vs HDMI TMDS Mode Selection**:
   Forced HDMI TMDS audio framing and muted DP_AUDIO (`0x61c1e0 + soff`) when using passive Mini-DP to HDMI adapters.

---

### 2. Ecosystem Modifications & Enhancements (Our Customizations)

#### A. Hardware Underscan (16:9 Overscan Elimination)
Televisions natively crop borders on 1080p inputs (overscan). Using Nouveau KMS RandR properties, we discovered the exact 16:9 proportional underscan boundaries:
```bash
xrandr --output DP-1 --set underscan on --set "underscan hborder" 48 --set "underscan vborder" 27
```
This restores all edge pixels (taskbars, window titles, conky) without distortion.

#### B. Smart Audio & Display Router with Audio-ELD Sensing & Single-Display Mode (`scripts/auto-audio-router.sh`)
* **The 5V Standby Blind Zone Trap**: Turning off a TV via remote keeps its HDMI receiver board powered on standby, holding the HPD line high (`DP-1 connected`). Naive detection methods that rely solely on `status=connected` mistakenly treat the TV as ON, turning off the laptop screen (`LVDS-1 --off`) and leaving the machine with zero responsive displays—locking out both physical users and NoMachine remote sessions.
* **The Triple-Defense Solution**:
  * **Protocol-Level Audio ELD Sensing**: The daemon inspects `/proc/asound/card0/eld*.0` for `eld_valid 1` and an active `monitor_name` (e.g. `SONIQ`). When the TV powers off to standby, its HDMI audio sink shuts down and ELD drops to 0, preventing false positives.
  * **True TV Single-Display Mode**: When the TV is truly active, `DP-1` is set as Primary 1080p60 (with 48/27 underscan), `LVDS-1` is set to `--off` in X11, and the hardware backlight (`/sys/class/backlight/nv_backlight/brightness`) is set to `0`. This eliminates mouse drift, window spawning on invisible screens, and light pollution in a dark room.
  * **Instant Standby/Off Fallback & NoMachine Adaptive Routing**: Within 1-2 seconds of TV power-off, the daemon automatically restores `LVDS-1` to 1280x800 Primary and resets backlight to 15. NoMachine lands cleanly on the 1080p TV display when the TV is on, and seamlessly lands on the 1280x800 laptop screen when the TV is off.

#### C. NoMachine Physical Desktop Access & Permission Hardening
To prevent NoMachine from dropping into a read-only mode during HDMI hotplugging:
1. Configure `/usr/NX/etc/server.cfg`:
   ```ini
   PhysicalDesktopMode 2
   ```
2. Grant user full administrator and trusted physical privileges:
   ```bash
   sudo /usr/NX/bin/nxserver --useredit <username> --administrator yes --trusted physical
   sudo /usr/NX/bin/nxserver --restart
   ```

#### D. Anti-2001 Boot RTC Time Freeze (`scripts/net-timesync.sh` & `patches/udev-fake-hwclock-guard.patch`)
* **Problem**: On vintage MacBooks with a dead PRAM coin battery, the hardware RTC resets to 2001-01-01 on every boot. antiX udev rule `/lib/udev/hwclock-set` unconditionally reads the dead RTC and clobbers system time at boot, breaking SSL/TLS certificates, apt, and NoMachine.
* **Fix**:
  1. Patch `/lib/udev/hwclock-set` to exit immediately if `/etc/fake-hwclock.data` exists (`patches/udev-fake-hwclock-guard.patch`).
  2. Install `scripts/net-timesync.sh` into runit boot sequence (`/etc/runit/rc-local/10-net-timesync.start`), synchronizing via HTTP Date headers and NTP within seconds of network availability.

#### E. Thorium M154 Penryn Heterogeneous 1080p VP9 Streaming & AV1 Blocking
* **The Linux Widevine L3 DRM Reality**: On Linux, Widevine L3 (software DRM) strictly caps H.264 (AVC) streams at **540p (960x540)**. Netflix **only permits 1080p playback via VP9 (`vp9-profile0-L40-dash-cenc`)**. Forcing `disableVP9: true` silently causes Netflix to drop resolution from 1080p to 540p.
* **The Golden Codec Combination (`New Netflix 1080p` Extension)**:
  * **`disableVP9: false` (CRITICAL)**: Injects `vp9-profile0-L40-dash-cenc` into manifest negotiation, enabling true 1080p streaming.
  * **`disableAV1: true` (CRITICAL)**: Strips all AV1 profiles (`av1-main-L20` through `L51`). AV1 software decoding complexity is 3x~5x higher than VP9; allowing AV1 immediately pins the Core 2 Duo CPU to 100% and drops 90% of frames.
  * **`disableAVChigh: false`**: Preserves standard AVC profile compatibility.
* **CPU / GPU Heterogeneous Decoupling Architecture**:
  * **CPU Responsibility**: Intel Core 2 Duo P8600 (Penryn 2.4GHz) utilizes hand-tuned SSE4.1 SIMD loops in FFmpeg / libvpx strictly for VP9 bitstream integer arithmetic and IDCT decoding.
  * **GPU Responsibility**: Decoded YUV frames are transferred into GPU textures via Zero-Copy (`--enable-zero-copy --use-gl=angle --use-angle=gl --enable-features=CanvasOopRasterization,VaapiVideoDecodeDisabled`). The 48 CUDA cores of the GeForce 320M execute YUV-to-RGB color space conversion, bi-linear 1080p upscaling, and hardware composition.
  * **Empirical Verification**: Dual-core CPU load stabilizes at **~76%** (with ~15% system headroom), temperature holds steady at **77°C~79°C** with fan at a quiet 2224 RPM, playing 1080p Netflix completely stutter-free!

---

### Repository Contents
- `patches/nouveau-mcp89-hdmi-audio-all-in-one.patch`: Consolidated kernel source patch against Linux 6.6 LTS.
- `patches/udev-fake-hwclock-guard.patch`: Udev defense patch preventing dead RTC from resetting system time.
- `packages/nouveau.ko`: Precompiled patched Nouveau kernel module for `6.6.119-antix.1-amd64-smp`.
- `packages/vmlinuz-*` & `packages/initrd.img-*`: Full precompiled kernel and matching initramfs.
- `scripts/install_module.sh`: Automated installer script for the kernel module and initramfs update.
- `scripts/auto-audio-router.sh`: ACPI lid-sensing display and audio router daemon.
- `scripts/net-timesync.sh`: Boot time synchronization daemon for systems with dead RTC batteries.
- `scripts/test_hdmi_audio.sh`: Quick ALSA unmute and audio playback test.
- `scripts/dump_hdmi_regs.py`: Diagnostic tool to dump SOR1 MMIO registers via `/dev/mem`.
- `SHA256SUMS`: Cryptographic verification hashes.

---

<a name="繁體中文"></a>
## 繁體中文

### 專案概述
本版本庫提供完整的 Linux 內核補丁、預編譯模組以及周邊生態配套腳本，徹底解決 NVIDIA MCP89 晶片組（GeForce 320M，搭載於 MacBookPro7,1、MacBook7,1、Macmini4,1）在開源 **Nouveau** 驅動下的**HDMI 長期靜音**、**電視過掃描邊框切除**、**外接關機假在線黑屏**、**主板斷電開機回退 2001 年**以及**瀏覽器老架構高清播放卡頓**等一系列深層軟硬體痛點。

---

### 1. 內核級 HDMI 音訊逆向與修復核心
結合 Envytools 暫存器逆向與真機 MMIO 運行時差分（`0x61c000 - 0x61d000`），修復了上游 Nouveau 驅動（`drivers/gpu/drm/nouveau/nvkm/engine/disp/gt215.c`）的四大缺陷：
1. **啟用 ACR 時脈再生封包發送**：上游代碼誤將 `ACR.CTRL`（`0x61c568 + soff`）第 0 位元清零，導致電視端音訊 PLL 無法鎖定。補丁強制開啟 bit 0。
2. **補全 CTS 與 N 值暫存器**：寫入標準 CTS 對照值（1080p60 148.5MHz 下 `148500 << 8`）及 48kHz（N=6144）、44.1kHz（N=5644）參數。
3. **規範 Audio InfoFrame 結構**：替換原驅動偽造數據，寫入標準 CEA-861 2 聲道 LPCM 檔頭（`0x00000201`）與負載（`0x00000170`）。
4. **被動轉接 TMDS 模式強制與 DP 靜音**：被動 Mini-DP 轉接時強制走 HDMI TMDS 協議，並關閉 DP_AUDIO（`0x61c1e0 + soff`），消除協議衝突。

---

### 2. 生態鏈魔改與深度調優細節（魔改精粹）

#### A. 16:9 硬體欠掃描（徹底消除電視過掃描切邊）
電視在接收 1080p 信號時預設開啟硬體過掃描（Overscan），導致工作列與邊緣內容被切除。透過 Nouveau 原生 KMS 屬性，實測出精確等比的 16:9 Underscan 邊框：
```bash
xrandr --output DP-1 --set underscan on --set "underscan hborder" 48 --set "underscan vborder" 27
```
邊角無損回正，字體銳利清晰。

#### B. 協議級音訊 ELD 探針與真電視單屏獨占路由（含 NoMachine 自適應導向）
* **待機 5V 偽在線盲區**：電視用遙控器關閉後，HDMI 接收晶片維持待機供電，Mini-DP 持續維持 HPD 高電位（`DP-1 connected`）。若單純依賴 `status` 判斷，系統會誤認電視開機而關閉筆電螢幕（`LVDS-1 --off`），導致整機無活動物理輸出，本機與 NoMachine 遠端連線同步陷入黑屏鎖死。
* **三重防線自癒架構**：
  * **協議級音訊 ELD 探針**：即時讀取核心 ALSA 節點 `/proc/asound/card0/eld*.0`，嚴格檢驗 `eld_valid 1` 與實體設備名稱（如 `SONIQ`）。電視待機或關閉時音訊晶片斷電、ELD 降為 0，徹底杜絕誤判。
  * **真電視單屏獨占模式**：電視真正開機時，自動設 `DP-1` 為 Primary 1080p60（含 48/27 欠掃描防溢邊），`LVDS-1` 徹底 `--off` 且寫入背光為 `0`（`/sys/class/backlight/nv_backlight/brightness`）。鼠標不再滑出電視邊界，視窗絕對置中，筆電物理零漏光、零功耗。
  * **電視關閉自癒退守與 NoMachine 導向**：電視一旦關閉（ELD 消失瞬間），守護行程於 1~2 秒內秒級切換 `LVDS-1` 為 Primary 1280x800 並秒亮背光（亮度 15）。電視開機時 NoMachine 直連 1080p 電視，電視關機時直連 1280x800 筆電，雙軌自適應。

#### C. NoMachine 實體桌面權限與穿透配置
防止遠端接入被限制為只讀或無法點擊：
1. 修改 `/usr/NX/etc/server.cfg`：
   ```ini
   PhysicalDesktopMode 2
   ```
2. 授予管理員與信任實體桌面權限：
   ```bash
   sudo /usr/NX/bin/nxserver --useredit <用戶名> --administrator yes --trusted physical
   sudo /usr/NX/bin/nxserver --restart
   ```

#### D. antiX 23/26 開機時間凍結修復 (`scripts/net-timesync.sh` & `patches/udev-fake-hwclock-guard.patch`)
* **病因**：老舊主板紐扣電池失效，每次重啟 RTC 歸零到 2001-01-01。udev `/lib/udev/hwclock-set` 開機強行將系統時鐘踢回 2001 年，造成 SSL/TLS 憑證失效、軟體源與 NoMachine 連線失敗。
* **對策**：
  1. 打上 `patches/udev-fake-hwclock-guard.patch`，檢測到 `/etc/fake-hwclock.data` 存在時立即退出，杜絕死 RTC 覆寫系統時間。
  2. 在 runit 開機鏈加入 `scripts/net-timesync.sh`，開機立即透過 HTTP Date 與 NTP 在聯網數秒內精確校時。

#### E. Thorium M154 Penryn 異構解耦 1080p VP9 串流與 AV1 熔斷攔截
* **Linux Widevine L3 DRM 真相**：在 Linux 平臺上，軟體級 Widevine L3 對 H.264（AVC）串流強制限制最高解析度為 **540p（960x540）**。Netflix **僅放行 VP9（`vp9-profile0-L40-dash-cenc`）支援 1080p**。先前若在擴展中強行寫死 `disableVP9: true`，會導致 Netflix 伺服器在協商時悄然降級為 540p。
* **黃金解碼組合策略（`New Netflix 1080p` 擴展）**：
  * **`disableVP9: false`（關鍵）**：放行 `vp9-profile0-L40-dash-cenc` 進入 Manifest 協商，順利索取真正的 1080p 串流。
  * **`disableAV1: true`（關鍵熔斷）**：徹底剔除所有 AV1 Profile（`av1-main-L20` 至 `L51`）。AV1 軟解運算複雜度比 VP9 高出 3~5 倍，在老舊 Penryn 上軟解 AV1 會瞬間引發 CPU 100% 滿載並丟失 90% 幀率。
  * **`disableAVChigh: false`**：保留標準相容性。
* **CPU / GPU 異構運算解耦架構**：
  * **CPU 分工**：Intel Core 2 Duo P8600（Penryn 2.4GHz）透過 FFmpeg / libvpx 針對 SSE4.1 優化的 SIMD 向量迴圈，**專注於 VP9 整數位元流熵解碼與逆離散餘弦變換（IDCT）**。
  * **GPU 分工**：解碼出的 YUV 像素緩衝區透過 Zero-Copy（`--enable-zero-copy --use-gl=angle --use-angle=gl --enable-features=CanvasOopRasterization,VaapiVideoDecodeDisabled`）直接上傳至顯存紋理，由 GeForce 320M 的 48 個著色器負責 **YUV $\to$ RGB 色彩轉換**、**1080p 畫面雙線性縮放** 與 **硬體合成**。
  * **實測數據**：雙核 CPU 總負載穩定在 **約 76%**（保留約 15% 系統響應餘裕），核心溫度壓制在 **77°C ~ 79°C**（風扇僅 2224 RPM 靜音運行），1080p 全螢幕播放無任何微卡頓！

---

<a name="简体中文"></a>
## 简体中文

### 项目概述
本代码库提供完整的 Linux 内核补丁、预编译模块及周边生态全套脚本，彻底解决 NVIDIA MCP89 芯片组（GeForce 320M，广泛用于 MacBookPro7,1、MacBook7,1、Macmini4,1）在开源 **Nouveau** 驱动下的 **HDMI 长期无声**、**电视过扫描切边**、**外接关机假在线黑屏**、**断电开机回退 2001 年**以及**老架构高清视频播放卡顿**等系统级顽疾。

---

### 1. 内核级 HDMI 音频修复核心
修复了 Nouveau 驱动（`drivers/gpu/drm/nouveau/nvkm/engine/disp/gt215.c`）四大缺陷：
1. **启用 ACR 时钟包发送**：强制开启 `ACR.CTRL`（`0x61c568 + soff`）bit 0，使电视音频 PLL 正常锁定时钟。
2. **补全 CTS 与 N 寄存器**：写入 1080p60 148.5MHz 标准 CTS（`148500 << 8`）及 48kHz（N=6144）、44.1kHz（N=5644）时钟参数。
3. **规整 Audio InfoFrame 结构**：替换为标准 CEA-861 2 声道 LPCM 规范（报头 `0x00000201`，负载 `0x00000170`）。
4. **被动转接 TMDS 模式锁定与 DP 互锁**：走标准 HDMI TMDS 封包并静音 DP_AUDIO。

---

### 2. 生态链魔改与深度调优细节（魔改精髓）

#### A. 16:9 硬件欠扫描（彻底消除电视边缘裁切）
外接电视 1080p 默认存在 Overscan 切边。通过 Nouveau KMS RandR 写入 16:9 等比 Underscan 边框：
```bash
xrandr --output DP-1 --set underscan on --set "underscan hborder" 48 --set "underscan vborder" 27
```
彻底还原任务栏与四周边界，告别画面裁剪。

#### B. 协议级音频 ELD 探针与真电视单屏独占路由（含 NoMachine 自适应导向）
* **待机 5V 伪在线盲区**：电视用遥控器关机后，HDMI 接收芯片维持待机供电，Mini-DP 仍维持 High HPD（`DP-1 connected`）。若单纯依赖 `status` 判定，系统会误认电视开机而将笔记本内建屏关闭（`LVDS-1 --off`），导致整机无物理输出，窗口管理器卡死，NoMachine 与本地双双陷入黑屏死锁。
* **三重防线自愈架构**：
  * **协议级音频 ELD 探针**：实时读取内核 ALSA 节点 `/proc/asound/card0/eld*.0`，严格检验 `eld_valid 1` 与实体设备名称（如 `SONIQ`）。电视待机或关机时音频芯片断电、ELD 降为 0，彻底杜绝误判。
  * **真电视单屏独占模式**：电视真正开机时，自动设 `DP-1` 为 Primary 1080p60（含 48/27 欠扫描防溢边），`LVDS-1` 彻底 `--off` 且将背光写入 `0`（`/sys/class/backlight/nv_backlight/brightness`）。鼠标不再滑出电视边界，窗口绝对居中，笔记本物理零漏光、零功耗。
  * **电视关机自愈退守与 NoMachine 导向**：电视一旦关闭（ELD 消失瞬间），守护进程在 1~2 秒内秒级切换 `LVDS-1` 为 Primary 1280x800 并秒亮背光（亮度 15）。电视开机时 NoMachine 直连 1080p 电视，电视关机时直连 1280x800 笔记本，双轨自适应。

#### C. NoMachine 物理桌面权限解锁
解决外接屏状态下被判定为只读会话及鼠标无法点击：
1. 配置 `/usr/NX/etc/server.cfg` 中 `PhysicalDesktopMode 2`。
2. 授予用户物理桌面完全信任：
   ```bash
   sudo /usr/NX/bin/nxserver --useredit <用户名> --administrator yes --trusted physical
   sudo /usr/NX/bin/nxserver --restart
   ```

#### D. antiX 23/26 时间冻结防御 (`scripts/net-timesync.sh` & `patches/udev-fake-hwclock-guard.patch`)
* **根因**：主板纽扣电池耗尽导致 RTC 永远重置为 2001 年，udev 脚本开机强行覆写系统时间，导致 TLS 证书全部报废。
* **方案**：
  1. 应用 `patches/udev-fake-hwclock-guard.patch` 拦截 udev 破坏性覆写。
  2. 通过 runit 开机启动 `scripts/net-timesync.sh`，在网络接通数秒内完成 HTTP Date/NTP 精确对时。

#### E. Thorium M154 Penryn 异构解耦 1080p VP9 串流与 AV1 熔断拦截
* **Linux Widevine L3 DRM 真相**：在 Linux 平台，软件级 Widevine L3 对 H.264（AVC）串流强制封顶为 **540p（960x540）**。Netflix **仅放行 VP9（`vp9-profile0-L40-dash-cenc`）支持 1080p**。此前若在插件中强行写死 `disableVP9: true`，会导致 Netflix 服务端在协商时悄然降级为 540p。
* **黄金解码组合策略（`New Netflix 1080p` 插件）**：
  * **`disableVP9: false`（关键）**：放行 `vp9-profile0-L40-dash-cenc` 参与 Manifest 协商，顺利拉取真正的 1080p 串流。
  * **`disableAV1: true`（关键熔断）**：彻底剔除所有 AV1 Profile（`av1-main-L20` 至 `L51`）。AV1 软解运算复杂度比 VP9 高出 3~5 倍，在老旧 Penryn 上软解 AV1 会瞬间引发 CPU 100% 满载并丢失 90% 帧率。
  * **`disableAVChigh: false`**：保留标准兼容性。
* **CPU / GPU 异构运算解耦架构**：
  * **CPU 分工**：Intel Core 2 Duo P8600（Penryn 2.4GHz）借助 FFmpeg / libvpx 针对 SSE4.1 优化的 SIMD 向量循环，**专职负责 VP9 整数码流熵解码与逆离散余弦变换（IDCT）**。
  * **GPU 分工**：解码产出的 YUV 像素缓冲区通过 Zero-Copy（`--enable-zero-copy --use-gl=angle --use-angle=gl --enable-features=CanvasOopRasterization,VaapiVideoDecodeDisabled`）直接上传至显存纹理，由 GeForce 320M 的 48 个着色器执行 **YUV $\to$ RGB 色彩转换**、**1080p 画面双线性缩放** 与 **硬件合成**。
  * **实测数据**：双核 CPU 总负载稳定在 **约 76%**（保留约 15% 系统响应余量），核心温度压制在 **77°C ~ 79°C**（风扇仅 2224 RPM 静音运转），1080p 全屏播放丝滑无卡顿！

---

### 许可证
本补丁遵循 Linux 内核原生 GPLv2 许可证。
