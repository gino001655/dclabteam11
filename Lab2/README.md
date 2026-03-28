# Lab2 Guideline

The roadmap of this lab:

1. Create project (same as lab1)
2. Implement the RSA256 core
3. Implement a Avalon master to control RS-232 and wrap your core
4. Build Qsys system
5. Compile and program (same as lab1)

## Implement the RSA256 Core
Before starting the introduction, I want to share an good concept
that I've learned when I interned at a hardware company.

> When you design an architecture, you design the dataflow first.
> Write Verilog only after you have make sure of all dataflow.

For example if we want to design a module for outputing all even numbers less than
a certain number, then we can design two modules:

module A: given n, counting from 0 to n-1

{5} -> {0, 1, 2, 3, 4}

module B: given a number, output if it is even.

{1, 4, 1, 5, 10, 0} -> {4, 10, 0}

Then the desired module is obtained by connecting A and B.

We intdoruce two very common but simple protocol dataflow.
The one wire protocol is quite simple: if "sender" set the val (valid signal)
to high, then the "sender" has prepared a valid data at that cycle.

    output val         ----> input val
    output dat1        ----> input dat1
    output [10:0] dat2 ----> input [10:0] dat2

Often the module cannot handle data at the moment, so another signal rdy (ready)
is used to stop the data transfer, which can be called as the two wire protocol.

    output val         ----> input  val
    input  rdy         <---- output rdy
    output dat1        ----> input  dat1
    output [10:0] dat2 ----> input [10:0] dat2

val (valid signal) means that "sender" want to send the data, and the sender must hold the data you want to send.
rdy (ready signal) means that "receiver" can accept the data.
If val is 0, then there is no effect whether rdy is 0 or 1 (aka don't care).
If val is 1, when "receiver" set rdy to 1 in this cycle, the "sender" may start the next transfer or
change the data in the next cycle.
On the other hand, you may assume the data hold if "receiver" set rdy to 0.

So now it's easy to understand the design for core module.

{a, e, n} -> core module -> {pow(a, e) mod n}

That's all, your mission is to implement a module that accept {a, e, n} and
output pow(a, e) mod n, conforming to the two wire protocol.
We also prepared a testbench for you (see appendix).

## Implement a Avalon Master to Control RS-232 and Wrap Your Core

The RS-232 module mainly has 2 functionalities.

1. Read a byte from computer
2. Write a byte from computer

Basically, your module (Avalon master) will work like this.

1. Receive 32 bytes from computer (n)
2. Receive 32 bytes from computer (e)
3. Receive 32 bytes from computer (a)
4. Compute
5. Send 31 bytes to computer (pow(a, e) mod n)
6. Go to 3

And you have to use Avalon protocol to actually read/write a byte from the RS-232 Qsys module.
The "read a byte" is done by the following sequence:

1. Read RX\_READY bit of the STATUS word
2. If it's 1, go to 3, else go to 1.
3. Read the lower byte of the RX word

Simliarly, the "write a byte" is done by the following sequence:

1. Read TX\_READY bit of the STATUS word
2. If it's 1, go to 3, else go to 1.
3. Write the lower byte of the TX word

If you understand the two wire protocol in the previous part,
then the Avalon protocol is just a variant and combination of the two wire protocol.
It's your task to read the Avalon protocol and RS-232 document for more details (available on NAS).
We also prepared a testbench for you (see appendix).

## Build Qsys system
Please follow the powerpoint.

# Requirements
The requirements are:

* Connect your PC and FPGA with RS-232 cable.
* Run the Connect your PC and FPGA with RS-232 cable,
  execute pc\_sw/rs232.py to decrypt enc.bin with key.bin (There will be hidden data).
* You have to install Python and serial library. Try to install that by yourself.

## Bonus

* Can you compute longer RSA?
* Design a better protocol so you don't have to reset every time.

# Appendix
## File Structure

* src/DE2\_115
	* All files related to the FPGA
* src/pc_python/
	* Python program for pc during RSA256 decryption
* src/tb_verilog/
	* Verilog testbench for RSA256 core and wrapper 
* src/Rsa256Core.sv
    * Implement RSA256 decryption algorithm here.
* src/Rsa256Wrapper.sv
    * Implement controller for RS232 protocol
    * Including reading check bits and read/write data. 

## Run pc_python program on pc

* Recommended python version: Python2
* Usagers
    * Windows: install python compiler
    * Mac/Linux: run with command line
* Command
```
    python rs232.py [COM? | /dev/ttyS0 | /dev/ttyUSB0]
```

## Testbench Usage

* Test Rsa256Core
```
    vcs <tb.sv> <Rsa256Core.sv> -full64 -R -debug_access+all -sverilog +access+rw
```
* Test Rsa256Wrapper 
```
    vcs <test_wrapper.sv> <PipelineCtrl.v> <PipelineTb.v> \ 
    <Rsa256Wrapper.sv> <Rsa256Core.sv> -full64 -R -debug_access+all -sverilog +access+rw
```
**NOTICE:** Please follow the exact argument order, wrong order may lead to error. 

## Python Reference Implementation

This can be used to check all temporary results and generate test cases.
Note that the size of plain text must be 31n.

Encode:
```
    python rsa.py e < plain.txt > cipher.bin
```

Decode:
```
    python rsa.py d < cipher.bin > plain.txt
```

# Bonus Feature: RSA 數位簽證與身分認證系統

我們在 Lab2 的基礎上實作了 **RSA 數位簽章 (Digital Signature)** 認證機制，確保只有持有授權私鑰的 PC 才能指揮 FPGA 進行解密工作。

### 核心功能
1. **雙核心並行運算**：FPGA 內部同時實例化兩個 `Rsa256Core`。一個負責執行 RSA 解密，另一個負責使用註冊的公鑰驗證 PC 傳來的數位簽章。
2. **模式切換與自動重置**：透過板子上的 `SW[17]` 進行模式切換。
    *   `SW[17] = 0` (往下)：**一般模式**。運作方式與原始 Lab2 完全相同。
    *   `SW[17] = 1` (往上)：**驗證模式**。啟用數位簽章檢查。
    *   **切換即重置**：撥動 `SW[17]` 會自動觸發硬體 Soft Reset，清空所有暫存器與已註冊的金鑰，不須額外按 `KEY[0]`。
3. **首位註冊機制 (First-Come-First-Serve)**：
    *   在驗證模式下，FPGA 具有「身分綁定」特性。Reset 後第一台與它溝通的 Python 腳本會將其公鑰 (Public Key) 註冊到 FPGA 硬體中。
    *   一旦註冊成功，FPGA 會「鎖定」該公鑰，直到下一次硬體重置為止。這能防止攻擊者在連線中途偷換身分。
4. **智慧交握協議**：設計了 `0xAA` (查詢)、`0xBB` (新 Session)、`0xCC` (續傳) 通訊機制。Python 腳本會自動偵測硬體狀態，即使中斷重啟也不會導致硬體 FSM 卡死。
5. **防禦回傳**：若簽章驗證失敗，FPGA 不會吐出明文，而是回傳嗆聲字串：`Nice try Diddy.`。

---

### 操作說明
#### 1. 準備測試金鑰對
在 `pc_python/` 目錄下執行金鑰產生器：
```bash
python generate_test_keys.py
```
這會產生 `pc_key/` 資料夾，內含數組完全合法的獨立 RSA 真鑰匙 (`keys`, `keys1`, `keys2`, `keys3`) 用於模擬不同使用者。

#### 2. 執行解密
直接執行更新過的 `rs232.py`，它會自動與 FPGA 溝通並決定解密流程：
```bash
python rs232.py COM3
```

---

### DEMO 流程參考
1.  **開啟驗證模式**：將 FPGA 的 `SW[17]` 撥到 ON。
2.  **正常註冊與解密**：
    *   確保 `pc_key/keys/` 下存放的是第一組使用者(ex:key1)的內容。
    *   執行 `python rs232.py COM3`。
    *   **現象**：FPGA 完成註冊，並成功產出解密後的 `dec.bin`。
    *   執行 `cp .\golden\enc3.bin .\enc.bin` 更改輸入檔案
    *   執行 `python rs232.py COM3`確認仍然能解密
3.  **駭客介入測試 (Blocked)**：
    *   **保持 FPGA 開啟且不切換開橋** 
    *   執行 `cp .\pc_key\keys2\* .\pc_key\keys\ -Force` 切換到其他使用者。
    *   執行 `python rs232.py COM3`。
    *   **現象**：Python 提示「Using existing Public Key on FPGA」，但隨後因
    為簽章與原註冊公鑰不符，FPGA 會回傳 `Nice try Diddy.`。

4.  **切換回原本的使用者**：
    *   執行 `cp .\pc_key\keys1\* .\pc_key\keys\ -Force` 切換回原使用者。
    *   執行 `python rs232.py COM3` 確認能解密

## 附錄：Qsys (Platform Designer) 整合流程
若需重新編輯或復刻硬體系統，請遵循以下步驟將 `SW[17]` 導入 Wrapper：

1. **編輯組件**：
    *   開啟 Platform Designer (`rsa_qsys.qsys`)。
    *   在 `Rsa_Wrapper` 組件上點擊右鍵選擇 **Edit...** 進入 Component Editor。
    *   切換到 **Signals & Interfaces** 頁籤。
    *   新增一個介面，類型選擇 **Conduit**，將其命名為 `sw_mode` (或其他易辨識名稱)。
    *   在該介面下新增一個 Signal，名稱設為 `i_sw_17`，**Width** 設為 1，**Signal Type** 務必填寫為 `export`。
    *   點擊 **Finish** 並存檔。

2. **匯出介面**：
    *   回到 Qsys 主畫面，在 `Rsa_Wrapper_0` 組件的 `sw_mode` 介面右側 **Export** 欄位連點兩下，將其匯出（建議命名為 `sw_mode`）。
    *   點擊右下角 **Generate HDL...** 重新產生硬體描述檔。

3. **頂層連線**：
    *   開啟頂層檔案 `src/DE2_115/DE2_115.sv`。
    *   在實例化 `rsa_qsys` 的區塊中，會多出一個 `.sw_mode_export` 的連接埠。
    *   將其連至實體按鈕：`.sw_mode_export (SW[17])`。
    *   儲存後於 Quartus 重新進行 **Full Compilation** 即可。

