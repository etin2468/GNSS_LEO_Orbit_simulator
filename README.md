# GNSS + LEO Orbit Simulator

這是一個 MATLAB 多星系軌道與接收機觀測值模擬器。程式以中央大學測站為接收機，模擬 GPS、GLONASS、Galileo 與 LEO 星系，並輸出幾何真值、帶誤差的 pseudorange，以及接近 RINEX observation 內容的 code、carrier phase、Doppler 與 C/N0。

## 檔案

- `simulator.m`: 主程式，計算軌道、可見衛星、量測值並輸出動畫與 MAT 資料。
- `kepler2ecef.m`: 將 Keplerian elements 轉換為 ECEF 位置與速度。
- `initializeMeasurementErrorModel.m`: 建立軌道、接收機/衛星時鐘、DCB 與 code noise。
- `applyMeasurementErrors.m`: 將基本誤差加入幾何距離，產生 pseudorange。
- `initializeSignalObservationModel.m`: 定義訊號頻率、波長、phase/Doppler/CN0 雜訊與追蹤情境。
- `applySignalObservationModel.m`: 產生 code、carrier phase、Doppler、C/N0，並更新 ambiguity、lock time 與 LLI。
- `distance_data.mat`: 輸出 `T_dist`、`T_obs`、`error_model` 與 `signal_model`。
- `orbit_animation.mp4`: 軌道動畫。

## 星系設定

| System ID | 星系 | 軌道高度 | 傾角 | 軌道面 x 每面衛星數 |
| --- | --- | --- | --- | --- |
| 1 | GPS | 20200 km | 55 deg | 6 x 4 |
| 2 | GLONASS | 19100 km | 64.8 deg | 3 x 8 |
| 3 | Galileo | 23220 km | 56 deg | 3 x 10 |
| 4 | LEO | 550 km | 97.7 deg | 6 x 10 |

接收機位置為 NCU，LLA = `[24.968223, 121.193490, 200]`。模擬時間為 24 小時，每 600 秒一個 epoch，elevation mask 為 10 deg。

## 基本距離誤差

`T_dist.Pseudorange_km` 使用下式：

```text
Pseudorange =
    True range
  + Orbit error projected to range
  + Receiver clock error
  - Satellite clock error
  + Differential code bias
  + Code noise
```

所有誤差狀態先以 meter 表示，亂數種子固定為 `42`，因此相同設定會產生相同資料。

目前基本距離模型尚未加入 ionosphere、troposphere、relativistic correction、phase wind-up 與 multipath。軌道誤差目前直接投影到量測距離，適合測試 range error；未來產生嚴格的 RINEX OBS/NAV 組合時，應把軌道誤差移至 navigation/ephemeris 資料，OBS 則由 truth orbit 產生。

## 訊號觀測模型

目前每個星系先模擬一個訊號：

| 星系 | 訊號 | 頻率 | 波長約值 | RINEX tracking code |
| --- | --- | ---: | ---: | --- |
| GPS | L1 C/A | 1575.42 MHz | 0.1903 m | 1C |
| GLONASS | G1 C/A | 1602.00 MHz | 0.1871 m | 1C |
| Galileo | E1 B/C | 1575.42 MHz | 0.1903 m | 1C |
| LEO | L1-like | 1575.42 MHz | 0.1903 m | 1X |

GLONASS 目前使用 G1 名義中心頻率。若要精確模擬 FDMA，需再加入每顆衛星的 frequency channel number。

Carrier phase 以 cycle 輸出：

```text
L = (true range + orbit error + receiver clock - satellite clock
     + phase bias + wavelength * integer ambiguity + phase noise) / wavelength
```

Doppler 以 Hz 輸出：

```text
D = -(range rate + receiver clock drift - satellite clock drift) / wavelength
    + Doppler noise
```

C/N0 以 dB-Hz 輸出，使用仰角相關模型；仰角越低，平均 C/N0 越低。

`initializeSignalObservationModel.m` 支援三種 scenario：

- `"clean"`: 不主動產生 cycle slip 或 outage，保留基本訊號雜訊。
- `"realistic"`: 目前預設；同樣不主動注入 slip/outage，適合先驗證 code/phase/Doppler 演算法。
- `"cycle-slip"`: 在低仰角提高 cycle slip 與短暫 outage 機率；ambiguity 會跳變，`LLI=1`，lock time 重新計算。

在 `simulator.m` 修改下列參數即可切換：

```matlab
[signal_model, observation_state] = initializeSignalObservationModel( ...
    t_array, sats_per_system, "realistic");
```

即使沒有主動 outage，衛星離開 elevation mask 後再次出現也視為 reacquisition，會重設 lock time、調整 ambiguity 並將該筆 `LLI` 設為 1。

## 輸出資料

`T_dist` 保留原本的距離與誤差分解欄位，供既有分析程式繼續使用。

`T_obs` 是後續 RINEX writer 的中間觀測表，主要欄位如下：

- `Code_m`: code pseudorange，meter。
- `Carrier_Phase_cycles`: carrier phase，cycle。
- `Doppler_Hz`: Doppler，Hz。
- `CN0_dBHz`: carrier-to-noise density，dB-Hz。
- `LLI`: loss-of-lock indicator；本模型以 `1` 表示 reacquisition 或 cycle slip。
- `LockTime_s`: 目前 ambiguity arc 的連續鎖定時間。
- `Ambiguity_cycles`: 模擬器內部的整數 ambiguity truth。
- `True_Range_m`、`Range_Rate_m_s`: 幾何真值，可用於驗證演算法。
- `Is_Valid`: outage 時為 `false`，該列的 C/L/D/S 為 `NaN`。
- `Signal`、`RINEX_Tracking_Code`: 訊號名稱與未來輸出 RINEX 時使用的 tracking code。

`Ambiguity_cycles`、真實距離和各誤差狀態屬於 simulator truth/debug 資訊，不應直接寫入正式 RINEX observation file。

## 執行

在 MATLAB 工作資料夾執行：

```matlab
simulator
```

完成後會產生 `distance_data.mat` 與軌道動畫。如果 `orbit_animation.mp4` 被其他程式鎖定，程式會改用帶 timestamp 的檔名；若影片輸出仍失敗，量測資料仍會正常保存。

下一階段可用 `T_obs` 實作 RINEX 3 observation writer，並把 observation truth 與帶誤差的 navigation/ephemeris 分成兩個資料產品。
