# GNSS + LEO Orbit Simulator

這個資料夾是一個 MATLAB 軌道模擬實驗，用 NCU 測站作為接收機位置，模擬 GPS、GLONASS、Galileo 與 LEO 衛星星系在一天內的可視情況。

## 主要檔案

- `simulator.m`: 主程式，產生多星系軌道動畫與距離量測資料。
- `kepler2ecef.m`: 將 Keplerian elements 轉成 ECEF 位置與速度。
- `initializeMeasurementErrorModel.m`: 建立可重現的量測誤差狀態。
- `applyMeasurementErrors.m`: 對可見衛星加入軌道、時鐘、DCB 與雜訊誤差。
- `distance_data.mat`: 主程式輸出的 table 資料，變數名稱為 `T_dist`。
- `orbit_animation.mp4`: 主程式輸出的 3D 動畫。

## 星系設定

| System ID | 系統 | 軌道高度 | 傾角 | 軌道面 x 每面衛星 |
| --- | --- | --- | --- | --- |
| 1 | GPS | 20200 km | 55 deg | 6 x 4 |
| 2 | GLONASS | 19100 km | 64.8 deg | 3 x 8 |
| 3 | Galileo | 23220 km | 56 deg | 3 x 10 |
| 4 | LEO | 550 km | 97.7 deg | 6 x 10 |

測站為 NCU，LLA = `[24.968223, 121.193490, 200]`。模擬時間為 24 小時，每 600 秒一筆 epoch，仰角遮罩為 10 度。

## 量測誤差模型

模擬現在同時輸出理想幾何距離與帶誤差的偽距：

```text
Pseudorange =
    True range
  + Orbit error projected to range
  + Receiver clock error
  - Satellite clock error
  + Differential code bias
  + Receiver noise
```

所有誤差分量都以 meter 記錄。模型使用固定亂數種子 `42`，所以重跑時結果可重現。若要調整誤差強度，修改 `initializeMeasurementErrorModel.m` 裡的 1-sigma 參數即可：

- `orbit_radial_sigma_m`
- `orbit_along_sigma_m`
- `orbit_cross_sigma_m`
- `orbit_random_walk_sigma_m`
- `receiver_clock_initial_m`
- `receiver_clock_random_walk_sigma_m`
- `satellite_clock_bias_sigma_m`
- `satellite_clock_random_walk_sigma_m`
- `dcb_sigma_ns`
- `noise_sigma_m`

目前尚未加入 ionosphere、troposphere、relativistic correction、phase wind-up 或 multipath 幾何模型；這些可以在 `applyMeasurementErrors.m` 中再以新的欄位擴充。

## 輸出欄位

`T_dist` 目前包含：

- `Time_s`: 模擬時間，單位 second。
- `System`: 系統編號，1=GPS、2=GLONASS、3=Galileo、4=LEO。
- `Sat_ID`: 系統內衛星 ID。
- `True_Distance_km`: 理想幾何距離，單位 km。
- `Pseudorange_km`: 加入誤差後的偽距，單位 km。
- `Total_Error_m`: 偽距與理想距離的差值，單位 m。
- `Elevation_deg`: 從 NCU 測站看的仰角。
- `Abs_Speed_km_s`: 衛星 ECEF 速度大小。
- `Radial_Vel_km_s`: 沿接收機視線方向的徑向速度。
- `Orbit_Error_m`: 軌道位置誤差投影到 range 後的距離誤差。
- `Receiver_Clock_Error_m`: 接收機時鐘偏差造成的距離誤差。
- `Satellite_Clock_Error_m`: 衛星時鐘偏差造成的距離誤差。
- `DCB_m`: differential code bias 造成的距離誤差。
- `Noise_m`: 接收機量測雜訊。

## 執行方式

在 MATLAB 中切到此資料夾後執行：

```matlab
simulator
```

完成後會更新 `orbit_animation.mp4` 與 `distance_data.mat`。

如果 `orbit_animation.mp4` 正被 Windows 或播放器鎖住，程式會自動改用 `orbit_animation_yyyymmdd_HHMMSS.mp4`。若影片輸出完全不可用，程式仍會完成距離資料輸出。
