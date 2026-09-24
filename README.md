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

#### B. Smart Audio & Display Router with ACPI Lid Sensing (`scripts/auto-audio-router.sh`)
* **The Blind Zone Trap**: Turning off the TV with a remote leaves the HDMI chip powered, keeping the Mini-DP HPD signal high (`DP-1 connected`). Naive scripts that turn off the laptop screen (`LVDS-1 --off`) leave the laptop with zero active displays, causing window managers to lock up and NoMachine to crash into a read-only shadow session (Display 1002).
* **The Solution**: The daemon reads `/proc/acpi/button/lid/*/state`:
  * **Lid Open**: Safe Dual-Display Mode. TV is set as Primary (1080p60 + 48/27 underscan), and the laptop display (LVDS-1 1280x800) remains ON as a failsafe anchor.
  * **Lid Closed**: Clamshell Mode. Turns off LVDS-1, dedicating full GPU bandwidth and VRAM to the TV.

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

#### E. Thorium M154 Penryn Ultra-Smooth 1080p H.264 Playback
* **GeForce 320M Limitation**: PureVideo HD VP4 hardware decoder supports only H.264 (AVC). It has zero hardware support for VP9 or AV1.
* **CPU Bottleneck**: The Intel Core 2 Duo P8600 (Penryn 2.4GHz, no AVX) hits 100% CPU load (severe lag and dropped frames) when software-decoding VP9/AV1.
* **The Solution**:
  * In `New Netflix 1080p` extension (`cadmium-playercore`): force `disableVP9: true`, `disableAV1: true`, and `disableAVChigh: false`. Strips VP9/AV1 profiles from manifest negotiation, forcing Netflix to stream `playready-h264hpl30/31/40-dash` (AVC High Profile).
  * In `enhanced-h264ify`: block VP9 and AV1 for YouTube and HTML5 video.
  * **Empirical Verification**: During 1080p Netflix streaming, the browser media decoding thread (`Media`) CPU load drops to **1.1%**, main renderer thread drops to **7.6%**, and total dual-core CPU usage stays under **15%**, running completely stutter-free!

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

#### B. 雙頭智感切換守護行程 (`scripts/auto-audio-router.sh`)
* **關機假在線盲區**：電視用遙控器關閉後，HDMI 晶片待機通電，Mini-DP 仍回傳 `DP-1 connected`。若直接將筆電螢幕熄滅（`LVDS-1 --off`），會造成全機無任何物理輸出，桌面管理器卡死且 NoMachine 崩潰成唯讀影子會話。
* **ACPI 開闔蓋感應**：腳本即時讀取 `/proc/acpi/button/lid/*/state`：
  * **開蓋狀態（Lid Open）**：安全雙屏模式。電視設為 Primary（1080p60 + 48/27 欠掃描），筆電內建螢幕（LVDS-1 1280x800）強制常亮作為實體掃描錨點，永不黑屏！
  * **闔蓋狀態（Lid Closed）**：閉蓋（Clamshell）模式。關閉內建屏，將全部顯存與算力專供電視。

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

#### E. Thorium M154 Penryn 老卡串流 1080p 極致軟解優化
* **硬體限制**：GeForce 320M (MCP89, PureVideo HD VP4) 僅支援 H.264 硬解，完全無 VP9/AV1 硬解。Core 2 Duo P8600 雙核軟解 VP9/AV1 時 CPU 負載瞬間達到 100%（嚴重掉幀卡頓）。
* **魔改優化**：
  * 修改 `New Netflix 1080p` 擴展（`cadmium-playercore`）：強制寫死 `disableVP9: true` 與 `disableAV1: true`，在協商階段剝除所有 VP9/AV1 請求，僅請求 `playready-h264hpl30/31/40-dash`（AVC High Profile）。
  * 搭配 `enhanced-h264ify` 阻截 YouTube VP9/AV1。
  * **實測數據**：1080p 播放時，解碼執行緒（`Media`）CPU 佔用僅 **1.1%**，Thorium 主執行緒僅 **7.6%**，雙核總負載低於 **15%**，畫面極致流暢！

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

#### B. 双屏智感路由守护进程 (`scripts/auto-audio-router.sh`)
* **假在线黑屏盲区**：遥控器关机后电视 HDMI 待机通电，Mini-DP 仍维持 High HPD。若单纯关屏（`LVDS-1 --off`），会导致整机无物理输出，窗口管理器卡死，NoMachine 降级为只读 Display 1002。
* **ACPI 开阖盖感知**：
  * **开盖状态**：安全双屏模式。电视为主屏（1080p60 + 欠扫描），笔记本内建屏（1280x800）保持点亮作为物理锚点，绝不黑屏。
  * **合盖状态**：Clamshell 模式。关闭内建屏，全算力与显存专供电视。

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

#### E. Thorium M154 Penryn 老卡串流 1080p 极致优化
* **硬件背景**：GeForce 320M 仅支持 H.264 硬解，无 VP9/AV1。P8600 软解 VP9/AV1 时双核 CPU 满载 100% 严重掉帧。
* **优化策略**：
  * 修改 `New Netflix 1080p`（`cadmium-playercore`）：强制 `disableVP9: true` 与 `disableAV1: true`，剥离全部 VP9/AV1 请求，仅请求 `playready-h264hpl*`。
  * 配合 `enhanced-h264ify` 阻断 YouTube VP9/AV1。
  * **实测数据**：1080p 播放时，音频视频解码线程（`Media`）CPU 仅 **1.1%**，Thorium 主线程仅 **7.6%**，双核总负载低于 **15%**，运行极为顺滑！

---

### 许可证
本补丁遵循 Linux 内核原生 GPLv2 许可证。
