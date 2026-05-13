#!/bin/bash
# ==============================================================================
#  Project: open-fpga-wsl (setup.sh)
#  Description: Automated Open Source FPGA Toolchain Installer for WSL (Ubuntu)
#  Author: arnongtx
#  Copyright: (c) 2026 arnongtx
#  License: MIT (SPDX-License-Identifier: MIT)
# ==============================================================================

GREEN='\033[0;32m'
BLUE='\033[0;34m'
RED='\033[0;31m'
NC='\033[0m'

echo -e "${BLUE}====================================================${NC}"
echo -e "${BLUE}   open-fpga-wsl: Automated FPGA Toolchain Setup    ${NC}"
echo -e "${BLUE}   Supports: Lattice iCE40 & ECP5 (VHDL Flow)       ${NC}"
echo -e "${BLUE}   Features: Isolate Build & VHPIDirect (C++ Debug) ${NC}"
echo -e "${BLUE}====================================================${NC}"

# 1. อัปเดตแพ็กเกจระบบ
echo -e "\n${BLUE}[1/4] Updating system packages...${NC}"
sudo apt update && sudo apt upgrade -y

# 2. ติดตั้ง Build Tools, Node.js, เครื่องมือแฟลชบอร์ด และ Debugger (GCC, G++, GDB)
echo -e "\n${BLUE}[2/4] Installing Make, CMake, Node.js, G++, and GDB...${NC}"
sudo apt install -y make cmake nodejs npm dfu-util gcc g++ gdb

# 3. ติดตั้ง FPGA Toolchain หลักรวมถึงสถาปัตยกรรม iCE40 และ ECP5
echo -e "\n${BLUE}[3/4] Installing FPGA tools (Yosys, GHDL, nextpnr, GTKWave, openfpgaloader)...${NC}"
sudo apt install -y yosys ghdl gtkwave openfpgaloader nextpnr-ice40 nextpnr-ecp5

# 4. ติดตั้ง netlistsvg ผ่าน npm
echo -e "\n${BLUE}[4/4] Installing netlistsvg for schematics...${NC}"
sudo npm install -g netlistsvg

# ====================================================
# สร้าง Workspace และสร้างโปรเจกต์ตัวอย่าง VHDL + C++
# ====================================================
echo -e "\n${BLUE}[Bonus] Creating workspace and sample projects...${NC}"
mkdir -p fpga-workspace/slides
mkdir -p fpga-workspace/projects/ice40_vhdl_blinky
mkdir -p fpga-workspace/projects/ecp5_vhdl_blinky

# --- ซอร์สโค้ดไฟล์ภาษา C++ สำหรับแชร์ฟังก์ชันระดับสูงผ่าน VHPIDirect ---
CPP_FUNC_CODE="#include <iostream>

// ใช้ extern \"C\" เพื่อล็อกโครงสร้าง Name Mangling ของ C++ ให้ทำงานร่วมกับ GHDL ได้
extern \"C\" {
    void print_cpp_msg(int counter_val) {
        std::cout << \"[C++ Side Host Log] VHPIDirect Link Success! Current Cycle Counter: \" 
                  << counter_val << std::endl;
    }
}"

echo "$CPP_FUNC_CODE" > fpga-workspace/projects/ice40_vhdl_blinky/sim_core.cpp
echo "$CPP_FUNC_CODE" > fpga-workspace/projects/ecp5_vhdl_blinky/sim_core.cpp

# --- ซอร์สโค้ดไฟกระพริบ VHDL พื้นฐาน ---
VHDL_CODE="library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity blinky is
    port (
        clk : in  std_logic;
        led : out std_logic
    );
end entity;

architecture rtl of blinky is
    signal counter : unsigned(23 downto 0) := (others => '0');
begin
    process(clk)
    begin
        if rising_edge(clk) then
            counter <= counter + 1;
        end if;
    end process;

    led <= counter(23);
end architecture;"

VHDL_TB="library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity blinky_tb is
end entity;

architecture sim of blinky_tb is
    signal clk : std_logic := '0';
    signal led : std_logic;

    procedure print_cpp_msg(val : integer);
    attribute foreign of print_cpp_msg : procedure is \"VHPIDIRECT print_cpp_msg\";
    procedure print_cpp_msg(val : integer) is begin end procedure;

begin
    clk <= not clk after 10 ns;

    uut: entity work.blinky
        port map (
            clk => clk,
            led => led
        );

    process(clk)
        variable cycle_count : integer := 0;
    begin
        if rising_edge(clk) then
            cycle_count := cycle_count + 1;
            if cycle_count mod 100 = 0 then
                print_cpp_msg(cycle_count);
            end if;
        end if;
    end process;

    process
    begin
        wait for 10 us; 
        assert false report \"Simulation Finished Successfully\" severity failure;
    end process;
end architecture;"

echo "$VHDL_CODE" > fpga-workspace/projects/ice40_vhdl_blinky/blinky.vhd
echo "$VHDL_CODE" > fpga-workspace/projects/ecp5_vhdl_blinky/blinky.vhd

echo "$VHDL_TB" > fpga-workspace/projects/ice40_vhdl_blinky/blinky_tb.vhd
echo "$VHDL_TB" > fpga-workspace/projects/ecp5_vhdl_blinky/blinky_tb.vhd

# ----------------------------------------------------
# 🧊 2. โครงสร้างโปรเจกต์ Lattice iCE40 (บิวด์ซอร์ส C++ พาสทรู)
# ----------------------------------------------------
cat << 'EOF' > fpga-workspace/projects/ice40_vhdl_blinky/ice40.pcf
set_io clk 35 
set_io led 40 
EOF

cat << 'EOF' > fpga-workspace/projects/ice40_vhdl_blinky/Makefile
# open-fpga-wsl | Lattice iCE40 VHDL & C++ Makefile
# Copyright (c) 2026 arnongtx
# Released under the MIT License

PROJ    = blinky
SRC     = $(PROJ).vhd
TB      = $(PROJ)_tb.vhd
CPP_SRC = sim_core.cpp
PCF     = ice40.pcf

DEVICE   ?= up5k
PACKAGE  ?= sg48
SIM_TIME ?= 10us

BUILD_DIR = build

OUT_JSON = $(BUILD_DIR)/$(PROJ).json
OUT_ASC  = $(BUILD_DIR)/$(PROJ).asc
OUT_BIN  = $(BUILD_DIR)/$(PROJ).bin
OUT_SVG  = $(BUILD_DIR)/schematic.svg
OUT_VCD  = $(BUILD_DIR)/waveform.vcd

all: init pack view

init:
	mkdir -p $(BUILD_DIR)

synth: init $(OUT_JSON)
$(OUT_JSON): $(SRC)
	yosys -m ghdl -p "ghdl $(SRC) -e $(PROJ); synth_ice40 -top $(PROJ) -json $@"

pnr: $(OUT_ASC)
$(OUT_ASC): $(OUT_JSON) $(PCF)
	nextpnr-ice40 --json $(OUT_JSON) --pcf $(PCF) --asc $@ --$(DEVICE) --package $(PACKAGE)

pack: $(OUT_BIN)
$(OUT_BIN): $(OUT_ASC)
	icepack $< $@

view: $(OUT_SVG)
$(OUT_SVG): $(OUT_JSON)
	netlistsvg $(OUT_JSON) -o $@

sim: init
	cd $(BUILD_DIR) && g++ -g -c ../$(CPP_SRC)
	cd $(BUILD_DIR) && ghdl -a -g ../$(SRC) ../$(TB)
	cd $(BUILD_DIR) && ghdl -e -g -Wl,sim_core.o -Wl,-lstdc++ $(PROJ)_tb
	-cd $(BUILD_DIR) && ./$(PROJ)_tb --vcd=waveform.vcd --stop-time=$(SIM_TIME)

debug: sim
	cd $(BUILD_DIR) && gdb ./$(PROJ)_tb

wave: sim
	gtkwave $(OUT_VCD)

prog: $(OUT_BIN)
	openFPGALoader -b icebreaker $<

clean:
	rm -rf $(BUILD_DIR)

.PHONY: all init synth pnr pack view sim debug wave prog clean
EOF

# ----------------------------------------------------
# 💎 3. โครงสร้างโปรเจกต์ Lattice ECP5 (บิวด์ซอร์ส C++ พาสทรู)
# ----------------------------------------------------
cat << 'EOF' > fpga-workspace/projects/ecp5_vhdl_blinky/ecp5.lpf
LOCATE COMP "clk" SITE "A10"; 
IOBUF PORT "clk" IO_TYPE=LVCMOS33;

LOCATE COMP "led" SITE "B11"; 
IOBUF PORT "led" IO_TYPE=LVCMOS33;
EOF

cat << 'EOF' > fpga-workspace/projects/ecp5_vhdl_blinky/Makefile
# open-fpga-wsl | Lattice ECP5 VHDL & C++ Makefile
# Copyright (c) 2026 arnongtx
# Released under the MIT License

PROJ    = blinky
SRC     = $(PROJ).vhd
TB      = $(PROJ)_tb.vhd
CPP_SRC = sim_core.cpp
LPF     = ecp5.lpf

DEVICE   ?= 25k
PACKAGE  ?= CABGA381
SPEED    ?= 6
SIM_TIME ?= 10us

BUILD_DIR = build

OUT_JSON   = $(BUILD_DIR)/$(PROJ).json
OUT_CONFIG = $(BUILD_DIR)/$(PROJ).config
OUT_BIT    = $(BUILD_DIR)/$(PROJ).bit
OUT_SVG    = $(BUILD_DIR)/schematic.svg
OUT_VCD    = $(BUILD_DIR)/waveform.vcd

all: init pack view

init:
	mkdir -p $(BUILD_DIR)

synth: init $(OUT_JSON)
$(OUT_JSON): $(SRC)
	yosys -m ghdl -p "ghdl $(SRC) -e $(PROJ); synth_ecp5 -top $(PROJ) -json $@"

pnr: $(OUT_CONFIG)
$(OUT_CONFIG): $(OUT_JSON) $(LPF)
	nextpnr-ecp5 --json $(OUT_JSON) --lpf $(LPF) --textcfg $@ --$(DEVICE) --package $(PACKAGE) --speed $(SPEED)

pack: $(OUT_BIT)
$(OUT_BIT): $(OUT_CONFIG)
	ecppack $< $@

view: $(OUT_SVG)
$(OUT_SVG): $(OUT_JSON)
	netlistsvg $(OUT_JSON) -o $@

sim: init
	cd $(BUILD_DIR) && g++ -g -c ../$(CPP_SRC)
	cd $(BUILD_DIR) && ghdl -a -g ../$(SRC) ../$(TB)
	cd $(BUILD_DIR) && ghdl -e -g -Wl,sim_core.o -Wl,-lstdc++ $(PROJ)_tb
	-cd $(BUILD_DIR) && ./$(PROJ)_tb --vcd=waveform.vcd --stop-time=$(SIM_TIME)

debug: sim
	cd $(BUILD_DIR) && gdb ./$(PROJ)_tb

wave: sim
	gtkwave $(OUT_VCD)

prog: $(OUT_BIT)
	openFPGALoader -b genericContainerFlashing $<

clean:
	rm -rf $(BUILD_DIR)

.PHONY: all init synth pnr pack view sim debug wave prog clean
EOF

# ----------------------------------------------------
# 📊 4. สร้างไฟล์โครงร่างสไลด์นำเสนอ (Marp Markdown)
# ----------------------------------------------------
cat << 'EOF' > fpga-workspace/slides/presentation.md
---
marp: true
theme: default
class: invert
paginate: true
backgroundColor: #1e1e1e
color: #f3f3f3
---

# 🛠️ open-fpga-wsl
### การติดตั้ง Open Source FPGA Toolchain บน WSL (Ubuntu)
**โดย: arnongtx**
คลังเก็บโค้ด: github.com

---

## 📦 เครื่องมือหลักในระบบ (Toolchain Ecosystem)
* **GHDL:** คอมไพล์และจำลองการทำงานภาษา VHDL
* **Yosys:** สังเคราะห์วงจรดิจิทัล (Logic Synthesis)
* **nextpnr:** จัดวางและหาเส้นทางพิน (Place & Route)
* **netlistsvg:** แปลงไฟล์ Netlist ออกมาเป็นผังวงจร (Schematic)
* **openFpgaLoader:** ดาวน์โหลดไฟล์บิตสตรีมลงบอร์ดจริง
* **GTKWave:** โปรแกรมแสดงกราฟคลื่นสัญญาณวงจรดิจิทัล

---

## 🧊 โครงสร้างกระบวนการออกแบบ (Design Flow)

### Lattice iCE40 Flow
`blinky.vhd` ➔ **GHDL + Yosys** ➔ `build/blinky.json` ➔ **nextpnr-ice40** ➔ `build/blinky.asc` ➔ **icepack** ➔ `build/blinky.bin`

### Lattice ECP5 Flow
`blinky.vhd` ➔ **GHDL + Yosys** ➔ `build/blinky.json` ➔ **nextpnr-ecp5** ➔ `build/blinky.config` ➔ **ecppack** ➔ `build/blinky.bit`

---

## 📂 โครงสร้างการแยกไฟล์บิวด์ (Clean Isolate Build Pattern)
ระบบจัดระเบียบไฟล์โดยแยกซอร์สโค้ดออกจากไฟล์คอมไพล์ชั่วคราวอย่างชัดเจน:
* ซอร์สโค้ดต้นฉบับ (`.vhd`, `.pcf`, `.lpf`, `.cpp`) จะถูกเก็บไว้ที่โฟลเดอร์หลักอย่างปลอดภัยไม่ปนเปื้อน
* ไฟล์ผลลัพธ์และไฟล์ระบบทั้งหมดจะถูกส่งไปสร้างและทำงานภายในโฟลเดอร์ `build/`
* เมื่อรันคำสั่ง `make clean` ระบบจะทำการลบโฟลเดอร์ `build/` ทิ้งทันที ทำให้โฟลเดอร์คลีน 100%

---

## 💻 การแยกคำสั่งทำงานใน Makefile (Granular Steps)
ระบบรองรับการรันคำสั่งแยกขั้นย่อย เพื่อความสะดวกในการตรวจสอบลอจิก:

* `make synth` : รันขั้นตอนสังเคราะห์วงจร (VHDL ➔ `build/blinky.json`)
* `make view` : เรียก **netlistsvg** สร้างผังวงจรอัตโนมัติ (`build/schematic.svg`)
* `make sim` / `make wave` : จำลองสถานะคลื่นและตรวจสอบผ่าน **GTKWave** โดยใช้ไฟล์คัตเอาต์ใน `build/`
* `make debug` : ดีบั๊กไล่ตรวจเช็คหน่วยความจำร่วมกับ **GDB Debugger**
* `make pnr` : จัดวางอุปกรณ์ลงบนโครงสร้างชิปตามพินเอาต์
* `make pack` : บีบอัดเป็นไฟล์บิตสตรีมพร้อมนำไปโปรแกรมลงบอร์ด

---

## 🎛️ การส่งพารามิเตอร์ควบคุม (Dynamic Arguments)
ไม่ต้องแก้ไขซอร์สโค้ดในไฟล์ ปรับเปลี่ยนผ่าน Terminal ได้ทันที:

### กำหนดรุ่นเกตและตัวถังชิปตอนบิวด์
```bash
make DEVICE=1k PACKAGE=tq144
make DEVICE=12k PACKAGE=CABGA256
```

### กำหนดขีดจำกัดเวลาเพื่อไม่ให้โปรแกรมจำลองสถานะค้าง
```bash
make wave SIM_TIME=500us
```

---

## 🔌 การทำ USB Forwarding ไปยัง WSL (Hardware Link)
เนื่องจากระบบ WSL มองไม่เห็นพอร์ต USB ของบอร์ดจริง จึงต้องใช้เครื่องมือเสริมช่วยบนฝั่งระบบปฏิบัติการ Windows:

1. ติดตั้งโปรแกรม **usbipd-win** บนคอมพิวเตอร์หลัก (Windows)
2. เปิด PowerShell (Admin) เช็คหมายเลข Bus ของบอร์ด:
   ```powershell
   usbipd list
   ```
3. ส่งอุปกรณ์เข้าสู่ระบบ WSL:
   ```powershell
   usbipd attach --wsl --busid <BUSID>
   ```
4. กลับมาที่ WSL Terminal แล้วรันคำสั่งแฟลชบอร์ด:
   ```bash
   make prog
   ```
EOF

# ====================================================
# ตรวจสอบความถูกต้องหลังติดตั้ง (Smoke Test)
# ====================================================
echo -e "\n${GREEN}====================================================${NC}"
echo -e "${GREEN}             Verifying Tool Versions                ${NC}"
echo -e "${GREEN}====================================================${NC}"

tools=("yosys" "ghdl" "nextpnr-ice40" "nextpnr-ecp5" "gtkwave" "openFPGALoader" "make" "gcc" "g++" "gdb")

for tool in "${tools[@]}"; do
    if command -v $tool &> /dev/null; then
        echo -e "${GREEN}✔ $tool:${NC} $( $tool --version 2>&1 | head -n 1 || $tool -v 2>&1 | head -n 1 )"
    else
        echo -e "${RED}✘ $tool: Not found${NC}"
    fi
done

echo -e "\n${GREEN}🎉 ทุกฟีเจอร์ติดตั้งสำเร็จในระบบ Isolate Build โฟลเดอร์สร้างไว้ที่ ./fpga-workspace ${NC}"
