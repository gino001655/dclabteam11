# DCLab Lab2 Report

**組別：Group 11**

---

## 1. File Structure

本次實驗專案的目錄結構及各檔案主要負責之功能如下：

* `src/`
    * `DE2_115/`：存放與開發板 FPGA 相關的腳位配置與周邊設定檔。
    * `pc_python/`：包含電腦端的 Python 腳本（`rs232.py` 等），負責在加解密過程中透過 RS-232 傳輸資料與密鑰至 FPGA。
    * `tb_verilog/`：包含 RSA Core 與 Wrapper 的 Verilog 測試檔 (Testbench)，用於模擬與除錯。
    * `Rsa256Core.sv`：包含 `Rsa256Core`、`RsaPrep` 與 `RsaMont`，為 RSA 256 加解密的核心模組，負責利用 Montgomery Algorithm 計算 $a^d \pmod n$。
    * `Rsa256Wrapper.sv`：Avalon Master 控制器，負責管理 RS-232 的資料接收與傳送，包裝了 RSA Core 的 I/O 介面，並以 Avalon 通訊協定與系統匯流排溝通。
* `rsa_qsys/`：Qsys 系統產生的相關設定與硬體描述檔。
* `README.md`：本次 Lab 的環境設置說明與要求細節。

---

## 2. System Architecture 

系統架構主要由 PC 端與 FPGA 控制端組成。PC 端透過執行 Python 腳本，將資料透過 RS-232 傳入 FPGA 端的 Qsys 系統。FPGA 中，`Rsa256Wrapper` 作為 Avalon Master，主動去監控 RS-232 的 STATUS 暫存器，抓取資料並送給底層的 `Rsa256Core` 計算。計算完畢後，Wrapper 再度將解密資料寫回 RS-232 的 TX 暫存器傳回 PC。

### Data Path
整個資料的流向 (Data Path) 流程如下：
1. **PC $\to$ RS-232 (RX)**：電腦端將 32 bytes 的 `n`、32 bytes 的 `d` 以及每一塊 32 bytes 的 Ciphertext (`enc`) 輪流透過 RS-232 序列埠傳入 FPGA。
2. **RS-232 $\to$ Wrapper**：`Rsa256Wrapper` 每當讀取 STATUS 發現 RX_OK_BIT 成立時，便將 RX 資料以 BYTE 為單位讀出，累加移位拼成 256 bits 的寬度。
3. **Wrapper $\to$ Core**：當 Wrapper 集齊所需的 256 bits Ciphertext 後，會連同 `n`、`d` 將資料匯入 `Rsa256Core` 並拉起 `i_start` 觸發計算。
4. **Core Internal Path**：`Rsa256Core` 內部將資料分配送至 `RsaPrep` (預處理轉換至 Montgomery 空間) 與兩組 `RsaMont` (Montgomery 乘法器)，執行基於 Square-and-Multiply 演算法的 256 次乘法運算。
5. **Core $\to$ Wrapper**：運算完成後，`o_finished` 觸發，Wrapper 將 248 bits (有效 31 bytes) 的解密明文資料 `o_a_pow_d` 存入暫存器。
6. **Wrapper $\to$ RS-232 (TX)**：Wrapper 檢查 STATUS 的 TX_OK_BIT 後，由高至低將 31 bytes 的明文依序寫入 TX 暫存器中。
7. **RS-232 $\to$ PC**：最後資料循 RS-232 線路傳遞回 PC 端進行重組顯示或寫檔。

---

## 3. Hardware Scheduling (FSM or Algorithm Workflow)

硬體排程分為 `Rsa256Wrapper` 的傳輸控制，以及 `Rsa256Core` 的計算排程兩個 FSM。

### `Rsa256Wrapper` FSM 排程
Wrapper 負責與 Avalon 匯流排的握手協定 (等待 `avm_waitrequest == 0` 後變換狀態)，主要有 4 個狀態：
* **`S_GET_KEY`**：從 RX_BASE 接收連續 64 bytes 資料。前 32 bytes 組合為除數 `n`，後 32 bytes 組合為私鑰 `d`。完成後跳轉至 `S_GET_DATA`。
* **`S_GET_DATA`**：從 RX_BASE 接收連續 32 bytes 資料並組合成 `enc` (Ciphertext)。接收完畢後啟動 `rsa_start` 並跳躍至 `S_WAIT_CALCULATE`。
* **`S_WAIT_CALCULATE`**：關閉 Avalon 讀寫，等待 `Rsa256Core` 的 `rsa_finished` 腳位被拉高。運算完成後，跳轉至 `S_SEND_DATA`。
* **`S_SEND_DATA`**：從高位元段擷取解密後的明文，分 31 bytes，每次偵測 TX_OK 之後寫入 TX_BASE。傳送完畢會直接跳回 `S_GET_DATA` 準備接收下一段密文 (bonus parameter persistence)。

### `Rsa256Core` Algorithm Workflow (FSM)
RSA核心採取 Montgomery 演算法 (Square & Multiply) 進行指數運算，狀態機如下：
* **`IDLE`**：等待 `i_start` 觸發。
* **`PREP_WAIT`**：啟動 `RsaPrep` 模組，將基底 $a$ 與 $1$ 分別乘上 $2^{256} \pmod n$ 進行預處理。完成後 $t \leftarrow a'$, $m \leftarrow 1'$，進入計算態。
* **`MONT_CALC`**：同時平行觸發兩組 Montgomery Multiplier (`mont1` 計算 $m \times t$，`mont2` 計算 $t \times t$)。
* **`MONT_WAIT`**：當兩組乘法器皆運算結束時，採用 Right-to-Left Square-and-Multiply 原理檢查 `i_d[count_reg]`。若目前 bit 為 1，則更新 `m_reg` 為 $m \times t$。不斷將 `t_reg` 更新為 $t^2$，直到迭代跑完 256 個 bit 為止，跳躍至 `MONT_LAST`。
* **`MONT_LAST` & `MONT_LAST_WAIT`**：進行最後一次乘法轉換，將 $m \times 1$ 送入 `mont1`，以消除之前加入的 $2^{256}$ Montgomery 因子，轉回一般數值表示。
* **`FINISH`**：完成轉換，拉出 `o_finished`。

---

## 4. Fitter Summary 截圖

*(請在此處貼上 Quartus 產生之 Fitter Summary 截圖，以展現 ALMs, Registers 等硬體資源消耗狀況)*

[此處預留給同學貼上截圖]

---

## 5. Timing Analyzer 截圖

*(請在此處貼上 Quartus Timing Analyzer 關於 Setup Time (WNS), Hold Time 等時序分析截圖)*

[此處預留給同學貼上截圖]

---

## 6. 遇到的問題與解決辦法，心得與建議

@陳致堯 您要寫嗎