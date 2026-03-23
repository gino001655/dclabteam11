# DCLab Lab1 Report

## 1. File Structure

專案的程式碼結構如下：

- **`src/`**
  - **`Top.sv`**: 遊戲核心邏輯模組。包含 LFSR（線性回饋移位暫存器）亂數產生器、時鐘分頻（控制亂數跳動速度）、以及負責控制遊戲流程的 FSM（有限狀態機）。
  - **`DE2_115/`**
    - **`DE2_115.sv`**: 硬體頂層模組（Top-level module）。負責將開發板的 I/O（如 Switch, Key, 7-Segment Display）連接至內部的各個子模組。
    - **`Debounce.sv`**: 按鍵防彈跳模組。確保按下 Start 按鍵時訊號穩定，避免觸發多次。
    - **`SevenHexDecoder.sv`**: 7 段顯示器解碼模組。將 4-bit 的二進位數值轉換為用於顯示的 7 段顯示器控制訊號。

---

## 2. System Architecture (Data Path)

系統架構與資料流路徑如下：

### **Inputs (輸入)**
- **`CLOCK_50`**: 50MHz 系統時脈。
- **`KEY[1]` (`i_rst_n`)**: 系統非同步重置 (Active-low)。
- **`KEY[0]` (`keydown`)**: 經由 `Debounce` 處理後的遊戲 Start/Restart 按鍵訊號。
- **`SW[3:0]` (`i_p1_guess`)**: 開關 0~3，作為 Player 1 的猜測數值輸入。
- **`SW[7:4]` (`i_p2_guess`)**: 開關 4~7，作為 Player 2 的猜測數值輸入。
- **`SW[17]` (`mode_gambling`)**: 切換遊戲模式。
  - `1`: 雙人賭博對戰模式（顯示 2 位玩家猜測數字，顯示贏家閃爍特效）。
  - `0`: 一般亂數模式（顯示中途擷取的亂數與前一次亂數）。

### **Processing Modules (處理模組)**
1. **`Debounce` (deb0)**: 接收 `KEY[0]` 與 50MHz 時脈，輸出穩定的 `keydown` 訊號給 `Top` 模組的 `i_start`。
2. **`Top` (top0)**: 遊戲運算核心：
   - 使用 LFSR 產生 4-bit (`0~15`) 偽隨機數。
   - 根據 `FSM` 狀態切換速度（從快速跳動漸漸變慢直到停止）。
   - 在停止後計算隨機亂數與 `p1_guess`, `p2_guess` 的距離 (`dist1`, `dist2`)，藉以判斷誰最接近且判定贏家。
   - 輸出: 目前亂數 (`random_value`), 玩家猜測值, 擷取值 (`random_capture`), 前次值 (`random_prev`), 及贏家閃爍訊號 (`p1_blink`, `p2_blink`)。
3. **Mux (資料選擇器 / DE2_115.sv 內 Combo Logic)**: 根據 `SW[17]`：
   - 將 Player 1 猜測值 `OR` 擷取的亂數 傳入 `hex_val_32`。
   - 將 Player 2 猜測值 `OR` 前次亂數 傳入 `hex_val_54`。
4. **`SevenHexDecoder` (seven_dec0 ~ seven_dec2)**: 將上述 4-bit 資料轉換為二位數十進制 (或 16 進位) 對應的 7-segment 訊號。

### **Outputs (輸出)**
- **`HEX0`, `HEX1`**: 顯示 `Top` 生成的即時 `random_value`。
- **`HEX2`, `HEX3`**: 顯示 Player 1 的猜測值 (或擷取值)。若在對戰模式且 Player 1 獲勝，則結合 `p1_blink` 訊號使畫面閃爍。
- **`HEX4`, `HEX5`**: 顯示 Player 2 的猜測值 (或前次亂數)。若 Player 2 獲勝，結合 `p2_blink` 使畫面閃爍。

---

## 3. Hardware Scheduling (FSM or Algorithm Workflow)

在 `Top.sv` 模組中，我們使用了一個含有三個狀態的有限狀態機 (FSM) 來控制遊戲的進行：

*   **`S_IDLE (2'd0)` : 等待狀態**
    *   **行為**：等待玩家啟動遊戲。不斷將外部的開關設定 (`i_p1_guess`, `i_p2_guess`) 讀入暫存器中。閃爍功能關閉。
    *   **轉移條件**：當偵測到 `i_start` (按鍵按下) 時，狀態轉換至 `S_RUN`。
    *   **額外動作**：離開 `S_IDLE` 瞬間，初始化切換速度（`speed_w = SPEED_INIT`），將上一次的亂數結果存入 `prev_w` (實作 Bonus 功能)。

*   **`S_RUN (2'd1)` : 亂數跳動狀態**
    *   **行為**：利用一個 Timer (`count_r`) 設定跳動頻率，當計數器到達門檻 (`speed_r`) 時，將 LFSR 的新值輸出（亂數跳動）。
    *   **減速機制**：每次更新數字後，增加門檻值 (`speed_w = speed_r + SPEED_STEP`)，使數字跳動頻率越來越慢，達到類似「輪盤」停下的效果。
    *   **中途擷取 (Bonus)**：如果在轉動時再次按下 `i_start`，則會重置跳動速度，並將當下的亂數存入 `capture_w` 以顯示於七段顯示器上。
    *   **轉移條件**：當跳動間隔 `speed_r` 大於設定的最大延遲 `SPEED_MAX` 時，視為轉盤停止，狀態移轉至 `S_DONE`。

*   **`S_DONE (2'd2)` : 結算與閃爍狀態**
    *   **行為**：維持最後抽出的亂數。
    *   **贏家判定**：計算亂數結果與兩位玩家猜測數字之間的差值絕對值（`dist1` 和 `dist2`）。
        *   若 `dist1 < dist2`：玩家 1 勝。
        *   若 `dist2 < dist1`：玩家 2 勝。
        *   若 `dist1 == dist2`：平手（兩者皆閃爍）。
    *   **特效處理**：使用 `blink_cnt_r` 定時切換 `blink_state_r` 的高低電位。如果玩家獲勝，其對應的閃爍訊號（`p1_blink_w` 或是 `p2_blink_w`）將與該高低電位同步，進而遮罩 HEX 輸出達到閃爍效果。
    *   **轉移條件**：當再次按下 `i_start`，狀態轉換回 `S_IDLE`，重置遊戲並準備下一回合。

---

## 4. Fitter Summary 截圖

*(請於此處貼上 Quartus 編譯完成後的 Fitter Summary 截圖)*

---

## 5. Timing Analyzer 截圖

*(請於此處貼上 TimeQuest/Timing Analyzer 通過時序分析的截圖，證明 setup/hold time 無違規)*

---

## 6. 遇到的問題與解決辦法，心得與建議

### 遇到的問題與解決辦法
*(這部分請根據你們實際製作時遇到的狀況自由修改)*
*   **問題 1**：在實作減速停止功能時，亂數跳動速度不如預期，或者無法正常停止。
    *   **解決辦法**：透過觀察和調整 `SPEED_INIT`, `SPEED_STEP`, 和 `SPEED_MAX` 的參數設定。確保計數器 `count_r` 以及 `speed_r` 的位元寬度足夠（需使用 26-bit 來匹配 50MHz 下的高延遲計數），防止 overflow 導致邏輯錯誤。
*   **問題 2**：在計算玩家猜測數字與亂數結果絕對值差 (Distance) 時出現數值 Underflow 而使判斷出錯。
    *   **解決辦法**：因為硬體不支援帶號數負值判斷的直接絕對值，改為使用 `always_comb` 內的三元運算子 `(A > B) ? (A - B) : (B - A)` 搭配較寬的 5-bit `dist` 變數來求得嚴謹的絕對誤差距離，順利解決。

### 心得與建議
此次 Lab1 綜合運用了組合邏輯與循序邏輯，並結合 FSM 開發了包含雙人賭博對戰功能以及中途擷取等 Bonus 的亂數產生器。
在實作的過程中... *(請自由補充學習到 SystemVerilog 的語法、除錯技巧、或是對開發板按鍵與顯示器連接的感觸)*。
