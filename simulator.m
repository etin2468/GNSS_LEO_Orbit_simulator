clear; clc; close all;

%% 環境與常數設定
% 地球重力常數與基礎參數
earth_r = 6378000; % 地球半徑 (近似值) [m]
GM = 3.986004418e14; % 地球標準重力參數 [m^3/s^2]

% 測站資訊 (NCU, 緯度、經度、高程)
NCU_station = [24.968223, 121.193490, 200];
phi_r = deg2rad(NCU_station(1));
lam_r = deg2rad(NCU_station(2));
NCU_XYZ = lla2ecef(NCU_station); % ECEF 坐標 [m]

% ECEF 轉 ENU 之旋轉矩陣 (Topocentric local frame)
R_ecef2enu = [-sin(lam_r),             cos(lam_r),             0;
              -sin(phi_r)*cos(lam_r), -sin(phi_r)*sin(lam_r),  cos(phi_r);
               cos(phi_r)*cos(lam_r),  cos(phi_r)*sin(lam_r),  sin(phi_r)];

% 動畫與模擬時間設定
time_step = 600; % 每步前進 10 分鐘 (600秒)，確保變化夠明顯
t_array = 0:time_step:86400; % 模擬一天 (24小時)

%% 建立 Walker 星系參數

% 1. GPS (原有 MEO)
a_GPS = 20200000 + earth_r; % GPS 大約高度 20200 km
e_GPS = 0;
i_GPS = deg2rad(55);
planes_GPS = 6;
sats_per_plane_GPS = 4;
n_GPS = sqrt(GM / a_GPS^3);

% 2. GLONASS
a_GLO = 19100000 + earth_r; % GLONASS 大約高度 19100 km
e_GLO = 0;
i_GLO = deg2rad(64.8); % 高傾角
planes_GLO = 3;
sats_per_plane_GLO = 8;
n_GLO = sqrt(GM / a_GLO^3);

% 3. Galileo
a_GAL = 23220000 + earth_r; % Galileo 大約高度 23220 km
e_GAL = 0;
i_GAL = deg2rad(56);
planes_GAL = 3;
sats_per_plane_GAL = 10;
n_GAL = sqrt(GM / a_GAL^3);

% 4. LEO 通訊或擴增衛星 (近似 97.7 度太陽同步軌道)
a_LEO = 550000 + earth_r;
e_LEO = 0;
i_LEO = deg2rad(97.7);
planes_LEO = 6;
sats_per_plane_LEO = 10;
n_LEO = sqrt(GM / a_LEO^3);

%% 初始化量測誤差模型
sats_per_system = [planes_GPS * sats_per_plane_GPS, ...
                   planes_GLO * sats_per_plane_GLO, ...
                   planes_GAL * sats_per_plane_GAL, ...
                   planes_LEO * sats_per_plane_LEO];
error_model = initializeMeasurementErrorModel(t_array, sats_per_system);

%% 初始化影片寫入器
video_filename = 'orbit_animation.mp4';
write_video = true;
try
    v = VideoWriter(video_filename, 'MPEG-4');
    v.FrameRate = 12;
    open(v);
catch ME
    warning('GPSsimulator:VideoFallback', '無法寫入 %s：%s。改用帶時間戳的影片檔名。', video_filename, ME.message);
    [~, base_name, ext_name] = fileparts(video_filename);
    timestamp = char(datetime('now', 'Format', 'yyyyMMdd_HHmmss'));
    video_filename = sprintf('%s_%s%s', base_name, timestamp, ext_name);
    try
        v = VideoWriter(video_filename, 'MPEG-4');
        v.FrameRate = 12;
        open(v);
    catch ME
        warning('GPSsimulator:VideoDisabled', '影片輸出停用：%s', ME.message);
        write_video = false;
        v = [];
    end
end

%% 初始化 3D 繪圖環境
fig = figure('Position', [100, 100, 800, 800], 'Color', 'w');
axis square; hold on; grid on;

% 畫地球 (透明球體)
[X_sphere, Y_sphere, Z_sphere] = sphere(40);
h_earth = surfl(X_sphere * earth_r, Y_sphere * earth_r, Z_sphere * earth_r);
set(h_earth, 'FaceAlpha', 0.5, 'EdgeColor', 'none');
shading interp; colormap('bone');

% 畫測站
scatter3(NCU_XYZ(1), NCU_XYZ(2), NCU_XYZ(3), 100, 'black', 'filled', '^');
text(NCU_XYZ(1)*1.1, NCU_XYZ(2)*1.1, NCU_XYZ(3)*1.1, 'NCU', 'FontWeight', 'bold');

% 畫參考軌跡線 (半透明)
theta_plot = linspace(0, 2*pi, 200);

% GPS 軌道 (紅)
for p = 1:planes_GPS
    RAAN = (p - 1) * (2*pi / planes_GPS);
    [Xp, Yp, Zp] = kepler2ecef(a_GPS, e_GPS, i_GPS, RAAN, 0, theta_plot, 0);
    plot3(Xp, Yp, Zp, 'Color', [0.8 0.4 0.4 0.3]); 
end
% GLONASS 軌道 (綠)
for p = 1:planes_GLO
    RAAN = (p - 1) * (2*pi / planes_GLO);
    [Xp, Yp, Zp] = kepler2ecef(a_GLO, e_GLO, i_GLO, RAAN, 0, theta_plot, 0);
    plot3(Xp, Yp, Zp, 'Color', [0.4 0.8 0.4 0.3]); 
end
% Galileo 軌道 (橘)
for p = 1:planes_GAL
    RAAN = (p - 1) * (2*pi / planes_GAL);
    [Xp, Yp, Zp] = kepler2ecef(a_GAL, e_GAL, i_GAL, RAAN, 0, theta_plot, 0);
    plot3(Xp, Yp, Zp, 'Color', [0.8 0.6 0.2 0.3]); 
end
% LEO 軌道 (藍)
for p = 1:planes_LEO
    RAAN = (p - 1) * (2*pi / planes_LEO);
    [Xp, Yp, Zp] = kepler2ecef(a_LEO, e_LEO, i_LEO, RAAN, 0, theta_plot, 0);
    plot3(Xp, Yp, Zp, 'Color', [0.4 0.6 0.8 0.3]); 
end

xlabel('X-axis (m)'); ylabel('Y-axis (m)'); zlabel('Z-axis (m)');
view(3);

% 準備動態更新的散點圖形物件 (全部衛星群: 灰色點)
h_gps_all = scatter3(nan, nan, nan, 5, [0.7 0.7 0.7], 'filled');
h_glo_all = scatter3(nan, nan, nan, 5, [0.7 0.7 0.7], 'filled');
h_gal_all = scatter3(nan, nan, nan, 5, [0.7 0.7 0.7], 'filled');
h_leo_all = scatter3(nan, nan, nan, 3, [0.7 0.7 0.7], 'filled');

% 可見衛星特顯點
h_gps_vis = scatter3(nan, nan, nan, 50, 'r', 'filled'); % 紅
h_glo_vis = scatter3(nan, nan, nan, 50, 'g', 'filled'); % 綠 
h_gal_vis = scatter3(nan, nan, nan, 50, [1 0.5 0], 'filled'); % 橘色
h_leo_vis = scatter3(nan, nan, nan, 40, 'b', 'filled'); % 藍

distance_log = []; % true range, pseudorange, and error components
elevation_mask = 10; % 仰角門檻 [度]

disp('開始進行時間循環並生成多星系混合動畫...');

%% 時間模擬主迴圈
for idx = 1:length(t_array)
    t_sim = t_array(idx);
    
    %% 第一階段：所有衛星軌道坐標更新
    % 1. GPS
    GPS_sats = []; id = 1;
    for p = 1:planes_GPS
        RAAN = (p - 1) * (2*pi / planes_GPS);
        for s = 1:sats_per_plane_GPS
            ta = (s - 1) * (2*pi / sats_per_plane_GPS) + n_GPS * t_sim; 
            [x, y, z, vx, vy, vz] = kepler2ecef(a_GPS, e_GPS, i_GPS, RAAN, 0, ta, t_sim);
            GPS_sats = [GPS_sats; id, x, y, z, vx, vy, vz];
            id = id + 1;
        end
    end
    % 2. GLONASS
    GLO_sats = []; id = 1;
    for p = 1:planes_GLO
        RAAN = (p - 1) * (2*pi / planes_GLO);
        for s = 1:sats_per_plane_GLO
            ta = (s - 1) * (2*pi / sats_per_plane_GLO) + n_GLO * t_sim;
            [x, y, z, vx, vy, vz] = kepler2ecef(a_GLO, e_GLO, i_GLO, RAAN, 0, ta, t_sim);
            GLO_sats = [GLO_sats; id, x, y, z, vx, vy, vz];
            id = id + 1;
        end
    end
    % 3. Galileo
    GAL_sats = []; id = 1;
    for p = 1:planes_GAL
        RAAN = (p - 1) * (2*pi / planes_GAL);
        for s = 1:sats_per_plane_GAL
            ta = (s - 1) * (2*pi / sats_per_plane_GAL) + n_GAL * t_sim;
            [x, y, z, vx, vy, vz] = kepler2ecef(a_GAL, e_GAL, i_GAL, RAAN, 0, ta, t_sim);
            GAL_sats = [GAL_sats; id, x, y, z, vx, vy, vz];
            id = id + 1;
        end
    end
    % 4. LEO
    LEO_sats = []; id = 1;
    for p = 1:planes_LEO
        RAAN = (p - 1) * (2*pi / planes_LEO);
        for s = 1:sats_per_plane_LEO
            ta = (s - 1) * (2*pi / sats_per_plane_LEO) + n_LEO * t_sim;
            [x, y, z, vx, vy, vz] = kepler2ecef(a_LEO, e_LEO, i_LEO, RAAN, 0, ta, t_sim);
            LEO_sats = [LEO_sats; id, x, y, z, vx, vy, vz];
            id = id + 1;
        end
    end
    
    %% 第二階段：視線與仰角計算過濾
    datasets = {GPS_sats, 1; GLO_sats, 2; GAL_sats, 3; LEO_sats, 4};
    vis_coords_all = {[], [], [], []}; % 儲存每種系統的可見坐標
    
    for sys = 1:4
        c_sats = datasets{sys, 1};
        c_sys_id = datasets{sys, 2};
        
        vis_coords = [];
        for k = 1:size(c_sats, 1)
            satXYZ = c_sats(k, 2:4);
            satVel = c_sats(k, 5:7);
            dx_ecef = (satXYZ - NCU_XYZ)';
            enu = R_ecef2enu * dx_ecef;
            
            range = norm(enu);
            elev = asind(enu(3) / range);
            
            if elev >= elevation_mask
                vis_coords = [vis_coords; satXYZ];
                abs_speed = norm(satVel);
                los_vec = dx_ecef / range;
                radial_vel = dot(satVel', los_vec);
                [pseudorange_m, ~, error_terms] = applyMeasurementErrors(error_model, c_sys_id, c_sats(k,1), idx, satXYZ, satVel, NCU_XYZ, range);
                distance_log = [distance_log; ...
                    t_sim, c_sys_id, c_sats(k,1), ...
                    range/1000, pseudorange_m/1000, error_terms.total_error_m, ...
                    elev, abs_speed/1000, radial_vel/1000, ...
                    error_terms.orbit_error_m, error_terms.receiver_clock_error_m, ...
                    error_terms.satellite_clock_error_m, error_terms.dcb_m, error_terms.noise_m];
            end
        end
        vis_coords_all{sys} = vis_coords;
    end
    
    %% 第三階段：更新當前影格圖型坐標
    set(h_gps_all, 'XData', GPS_sats(:,2), 'YData', GPS_sats(:,3), 'ZData', GPS_sats(:,4));
    set(h_glo_all, 'XData', GLO_sats(:,2), 'YData', GLO_sats(:,3), 'ZData', GLO_sats(:,4));
    set(h_gal_all, 'XData', GAL_sats(:,2), 'YData', GAL_sats(:,3), 'ZData', GAL_sats(:,4));
    set(h_leo_all, 'XData', LEO_sats(:,2), 'YData', LEO_sats(:,3), 'ZData', LEO_sats(:,4));
    
    handles_vis = [h_gps_vis, h_glo_vis, h_gal_vis, h_leo_vis];
    for sys = 1:4
        coords = vis_coords_all{sys};
        if ~isempty(coords)
            set(handles_vis(sys), 'XData', coords(:,1), 'YData', coords(:,2), 'ZData', coords(:,3));
        else
            set(handles_vis(sys), 'XData', nan, 'YData', nan, 'ZData', nan);
        end
    end
    
    title(sprintf('Multi-Constellation Animation (Time = %d s)', t_sim));
    drawnow;
    
    % 寫入影片
    if write_video
        frame = getframe(fig);
        writeVideo(v, frame);
    end
end

if write_video
    close(v);
    disp(['動畫生成完畢，已儲存於目錄下: ', video_filename]);
else
    disp('動畫輸出已略過，距離資料仍會儲存。');
end

%% 紀錄與匯出
% System ID: 1=GPS, 2=GLONASS, 3=Galileo, 4=LEO
T_dist = array2table(distance_log, 'VariableNames', {'Time_s', 'System', 'Sat_ID', ...
    'True_Distance_km', 'Pseudorange_km', 'Total_Error_m', ...
    'Elevation_deg', 'Abs_Speed_km_s', 'Radial_Vel_km_s', ...
    'Orbit_Error_m', 'Receiver_Clock_Error_m', 'Satellite_Clock_Error_m', 'DCB_m', 'Noise_m'});
save('distance_data.mat', 'T_dist', 'error_model');
disp('----------------- 多系統可見衛星分析預覽 (前五筆) ---------------');
disp('  System: 1=GPS, 2=GLO, 3=GAL, 4=LEO');
disp(head(T_dist, 5));
