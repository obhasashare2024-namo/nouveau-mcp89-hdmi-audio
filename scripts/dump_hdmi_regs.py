#!/usr/bin/env python3
"""
Dump NVIDIA MCP89 / GT215 SOR1 HDMI Audio MMIO Registers via /dev/mem
Must be run as root (sudo python3 dump_hdmi_regs.py).
"""
import sys
import mmap
import struct
import os

if os.geteuid() != 0:
    print("Error: Must be run as root to access /dev/mem.", file=sys.stderr)
    sys.exit(1)

BAR0_BASE = 0xd2000000
MMIO_OFFSET = BAR0_BASE + 0x610000
MAP_SIZE = 0x10000

REGS = [
    (0x61cd00, "AUDIO_INFO.CTRL (Bit 0 = Audio packet enable)"),
    (0x61cd08, "AUDIO_INFO.HDR  (InfoFrame Header)"),
    (0x61cd0c, "AUDIO_INFO.PB0  (PB0 Checksum / PB1 Channels)"),
    (0x61cd10, "AUDIO_INFO.PB4  (PB2-5 Format)"),
    (0x61cd68, "ACR.CTRL        (Bit 0 = ACR enable)"),
    (0x61cd6c, "ACR.CTS_32K     (32kHz CTS value)"),
    (0x61cd70, "ACR.N_32K       (32kHz N value)"),
    (0x61cd74, "ACR.CTS_44K1    (44.1kHz CTS value)"),
    (0x61cd78, "ACR.N_44K1      (44.1kHz N value)"),
    (0x61cd7c, "ACR.CTS_48K     (48kHz CTS value)"),
    (0x61cd80, "ACR.N_48K       (48kHz N value)"),
    (0x61cda4, "HDMI_CTRL       (Bit 30 = HDMI enable, Sample Flat, Rekey)"),
    (0x61cdd0, "SPARE/HW_CTS    (Hardware CTS control)"),
    (0x61c9e0, "DP_AUDIO        (Bit 0 = DP Audio enable)"),
    (0x617330, "AUDIO.CNTRL0    (Audio Source Select / Buffer Config)"),
    (0x61733c, "AUDIO.N         (Bit 28 = Lookup Enable)"),
]

def main():
    try:
        with open("/dev/mem", "r+b") as f:
            mm = mmap.mmap(f.fileno(), MAP_SIZE, offset=MMIO_OFFSET)
            print(f"=== NVIDIA MCP89 / GT215 SOR1 Audio MMIO Registers (Base: 0x{BAR0_BASE:08x}) ===")
            for reg, desc in REGS:
                offset_in_page = reg - 0x610000
                val = struct.unpack("<I", mm[offset_in_page:offset_in_page+4])[0]
                print(f"  0x{reg:06x}: 0x{val:08x}  # {desc}")
            mm.close()
    except Exception as e:
        print(f"Error reading MMIO: {e}", file=sys.stderr)
        sys.exit(1)

if __name__ == "__main__":
    main()
