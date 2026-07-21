# GNSS + LEO Orbit Simulator

這是一個 MATLAB 多星系衛星軌道與接收器觀測資料模擬器。模擬器建立 GPS、GLONASS、Galileo 與 LEO 星座，從 NCU 地面站計算可見衛星，並輸出：

- RINEX 3.05 observation file：code、carrier phase、Doppler、C/N0 與 LLI。
- SP3-d FIN product：完全正確的模擬軌道與實際衛星鐘差。
- SP3-d RAP product：帶有 RAC 軌道產品誤差與鐘產品估計誤差的軌道產品。
- `distance_data.mat`：完整 truth、觀測值、誤差狀態及產品表格。
- `orbit_animation.mp4`：星座與可見衛星動畫。

FIN/RAP 是此模擬器中的產品品質分類，用來模仿 IGS final/rapid 產品的使用方式；輸出不是官方 IGS 產品。

## 主要檔案

- `simulator.m`：主程式與輸出流程。
- `kepler2ecef.m`：Kepler 軌道狀態轉 ECEF 座標及速度。
- `initializeMeasurementErrorModel.m`：軌道、接收器鐘、衛星鐘、DCB 與 code noise。
- `applyMeasurementErrors.m`：產生 pseudorange 誤差項。
- `initializeSignalObservationModel.m`：訊號頻率、ambiguity、phase/Doppler noise、cycle slip 與 outage。
- `applySignalObservationModel.m`：產生 code、carrier phase、Doppler、C/N0、LLI 與 lock time。
- `racErrorToEcef.m`：將 radial/along/cross-track 誤差轉為 ECEF。
- `generatePreciseProducts.m`：建立 FIN 與 RAP 的衛星位置/鐘差表格。
- `writeRinexObs.m`：輸出 RINEX 3.05 mixed observation file。
- `writeSp3Product.m`：輸出 mixed-system SP3-d position/clock product。

## 星座設定

| System ID | 星系 | 高度 | 傾角 | 軌道面 x 每面衛星 |
| --- | --- | ---: | ---: | ---: |
| 1 | GPS | 20200 km | 55 deg | 6 x 4 |
| 2 | GLONASS | 19100 km | 64.8 deg | 3 x 8 |
| 3 | Galileo | 23220 km | 56 deg | 3 x 10 |
| 4 | LEO | 550 km | 97.7 deg | 6 x 10 |

接收站為 NCU，LLA 為 `[24.968223, 121.193490, 200]`。模擬時間為 24 小時，間隔 600 秒，包含首尾共 145 個 epoch；elevation mask 為 10 deg。

## 觀測模型

Pseudorange 使用：

```text
P = geometric range
  + receiver clock
  - satellite clock
  + DCB
  + code noise
```

Carrier phase 使用：

```text
L = (geometric range
     + receiver clock - satellite clock
     + phase bias + wavelength * integer ambiguity + phase noise)
    / wavelength
```

Doppler 使用：

```text
D = -(range rate + receiver clock drift - satellite clock drift)
    / wavelength
    + Doppler noise
```

軌道誤差預設不直接加入 OBS，而是寫入 RAP SP3。如此同一份觀測檔搭配 FIN 或 RAP 解算時，殘差會由所使用的產品自然產生，不會將同一個軌道誤差重複計算。`T_dist.Orbit_Error_m` 保留該誤差投影值供分析，`Applied_Orbit_Error_m` 預設為零。

若要重現舊式「直接污染量測距離」的實驗，可設定：

```matlab
error_model.apply_orbit_error_to_observation = true;
```

但此模式不應再搭配含有相同軌道誤差的 RAP 產品進行效能比較。

## 訊號與追蹤事件

| 星系 | 訊號 | 頻率 | RINEX tracking code |
| --- | --- | ---: | --- |
| GPS | L1 C/A | 1575.42 MHz | 1C |
| GLONASS | G1 C/A | 1602.00 MHz | 1C |
| Galileo | E1 B/C | 1575.42 MHz | 1X |
| LEO | L1-like | 1575.42 MHz | 1X |

`initializeSignalObservationModel.m` 支援：

- `"clean"`：關閉 cycle slip 與 outage，保留一般量測雜訊。
- `"realistic"`：預設模式，保留一般訊號雜訊但不主動注入 slip/outage。
- `"cycle-slip"`：提高 slip/outage 機率，方便測試 ambiguity reset 與 LLI。

Outage 的 C/L/D/S 設為 `NaN`；重新捕獲或 cycle slip 時 `LLI=1`，更新 ambiguity 並重設 lock time。

## RINEX OBS 輸出

預設檔名：

```text
NCUS00TWN_U_20260010000_01D_10M_MO.rnx
```

輸出 observation types：

- GPS：`C1C L1C D1C S1C`
- GLONASS：`C1C L1C D1C S1C`
- Galileo：`C1X L1X D1X S1X`

RINEX 3.05 沒有通用 LEO constellation system code，因此 LEO 觀測保留在 `T_obs`，不寫入這份標準 RINEX OBS。

## FIN/RAP SP3 輸出

預設檔名遵循 IGS long filename 的命名風格：

```text
SIM0OPSFIN_20260010000_01D_10M_ORB.SP3
SIM0OPSRAP_20260010000_01D_10M_ORB.SP3
```

兩個檔案均為 SP3-d mixed-system position product，包含：

- `G01-G24`：GPS
- `R01-R24`：GLONASS
- `E01-E30`：Galileo
- `L01-L60`：LEO
- 位置單位：km，寫入 `P` record。
- 衛星鐘差單位：microsecond，寫入同一個 `P` record。
- 時間系統：GPS。

FIN 內容：

```text
position = simulator truth position
clock    = actual simulated satellite clock
```

RAP 內容：

```text
position = truth position + RAC orbit product error transformed to ECEF
clock    = actual satellite clock + independent rapid clock product error
```

目前的固定亂數種子使結果可重現：measurement error seed 為 `42`，RAP clock product error seed 為 `27182`。

## MAT 輸出

`distance_data.mat` 包含：

- `T_dist`：幾何距離、pseudorange 與各誤差分解。
- `T_obs`：code、carrier phase、Doppler、C/N0、LLI、lock time 與 truth 欄位。
- `T_fin`、`T_rap`：寫入兩個 SP3 的完整衛星狀態。
- `error_model`、`signal_model`、`precise_product_model`：可重現的模型參數與誤差狀態。
- RINEX/SP3 metadata 與 write summary。

## 執行方式

在 MATLAB 工作目錄中執行：

```matlab
simulator
```

## 格式參考

- [RINEX 3.05 specification](https://files.igs.org/pub/data/format/rinex305.pdf)
- [SP3-d specification](https://files.igs.org/pub/data/format/sp3d.pdf)
- [IGS long product filename guideline](https://files.igs.org/pub/resource/guidelines/Guideline_for_the_transition_of_the_IGS_products_to_IGS20_and_long_filenames_v2.0.pdf)
