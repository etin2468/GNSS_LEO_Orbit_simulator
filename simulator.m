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
% MEO Walker 星系 (近似 GPS)
a_MEO = 20000000 + earth_r;
e_MEO = 0;
i_MEO = deg2rad(55);
planes_MEO = 6;
sats_per_plane_MEO = 4;
n_MEO = sqrt(GM / a_MEO^3); % MEO 平均運動速度 (rad/s)

% LEO Walker 星系 (近似基礎通訊星座，依您修改的 97.7 度太陽同步軌道)
a_LEO = 550000 + earth_r;
e_LEO = 0;
i_LEO = deg2rad(97.7);
planes_LEO = 6;
sats_per_plane_LEO = 10;
n_LEO = sqrt(GM / a_LEO^3); % LEO 平均運動速度 (rad/s)

%% 初始化影片寫入器
video_filename = 'orbit_animation.mp4';
v = VideoWriter(video_filename, 'MPEG-4');
v.FrameRate = 12; % 每秒播 12 幀，一天變化約 12 秒內播完
open(v);

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
for p = 1:planes_MEO
    RAAN_MEO = (p - 1) * (2*pi / planes_MEO);
    [Xp, Yp, Zp] = kepler2ecef(a_MEO, e_MEO, i_MEO, RAAN_MEO, 0, theta_plot, 0);
    plot3(Xp, Yp, Zp, 'Color', [0.8 0.4 0.4 0.3]); % 淺紅色半透明
end
for p = 1:planes_LEO
    RAAN_LEO = (p - 1) * (2*pi / planes_LEO);
    [Xp, Yp, Zp] = kepler2ecef(a_LEO, e_LEO, i_LEO, RAAN_LEO, 0, theta_plot, 0);
    plot3(Xp, Yp, Zp, 'Color', [0.4 0.6 0.8 0.3]); % 淺藍色半透明
end

xlabel('X-axis (m)'); ylabel('Y-axis (m)'); zlabel('Z-axis (m)');
view(3);

% 準備動態更新的散點圖形物件 (加快動畫繪圖效率)
h_meo_all = scatter3(nan, nan, nan, 5, [0.7 0.7 0.7], 'filled');
h_leo_all = scatter3(nan, nan, nan, 3, [0.7 0.7 0.7], 'filled');
h_meo_vis = scatter3(nan, nan, nan, 40, 'r', 'filled');
h_leo_vis = scatter3(nan, nan, nan, 40, 'b', 'filled');

distance_log = []; % 紀錄矩陣，格式: [Time(s), 系統(1=MEO,2=LEO), ID, 距離(km), 仰角(deg), 絕對速度(km/s),徑向速度(km/s)]
elevation_mask = 10; % 仰角門檻 [度]

disp('開始進行時間循環兵生成動畫擷取...');

%% 時間模擬主迴圈
for idx = 1:length(t_array)
    t_sim = t_array(idx);
    
    % 計算 MEO 全球網
    MEO_sats = []; id = 1;
    for p = 1:planes_MEO
        RAAN = (p - 1) * (2*pi / planes_MEO);
        for s = 1:sats_per_plane_MEO
            ta0 = (s - 1) * (2*pi / sats_per_plane_MEO);
            ta = ta0 + n_MEO * t_sim; % 真近點角隨著時間推移 (加入平均運動速度)
            [x, y, z, vx, vy, vz] = kepler2ecef(a_MEO, e_MEO, i_MEO, RAAN, 0, ta, t_sim);
            MEO_sats = [MEO_sats; id, x, y, z, vx, vy, vz];
            id = id + 1;
        end
    end
    
    % 計算 LEO 全球網
    LEO_sats = []; id_L = 1;
    for p = 1:planes_LEO
        RAAN = (p - 1) * (2*pi / planes_LEO);
        for s = 1:sats_per_plane_LEO
            ta0 = (s - 1) * (2*pi / sats_per_plane_LEO);
            ta = ta0 + n_LEO * t_sim; % 真近點角隨著時間推移 (加入平均運動速度)
            [x, y, z, vx, vy, vz] = kepler2ecef(a_LEO, e_LEO, i_LEO, RAAN, 0, ta, t_sim);
            LEO_sats = [LEO_sats; id_L, x, y, z, vx, vy, vz];
            id_L = id_L + 1;
        end
    end
    
    %% 篩選可視衛星並計算真實幾何距離
    vis_MEO_xyz = [];
    for k = 1:size(MEO_sats, 1)
        satXYZ = MEO_sats(k, 2:4);
        satVel = MEO_sats(k, 5:7); % [vx, vy, vz]
        dx_ecef = (satXYZ - NCU_XYZ)';
        enu = R_ecef2enu * dx_ecef;
        range = norm(enu); % 距離
        elev = asind(enu(3) / range);
        if elev >= elevation_mask
            vis_MEO_xyz = [vis_MEO_xyz; satXYZ];
            
            % 計算速度特徵
            abs_speed = norm(satVel); % 絕對軌道速率
            line_of_sight_vec = dx_ecef / range; % 視線方向向量
            radial_vel = dot(satVel', line_of_sight_vec); % 視線上的徑向互近速度(Doppler核心參數)
            
            distance_log = [distance_log; t_sim, 1, MEO_sats(k,1), range/1000, elev, abs_speed/1000, radial_vel/1000];
        end
    end
    
    vis_LEO_xyz = [];
    for k = 1:size(LEO_sats, 1)
        satXYZ = LEO_sats(k, 2:4);
        satVel = LEO_sats(k, 5:7); % [vx, vy, vz]
        dx_ecef = (satXYZ - NCU_XYZ)';
        enu = R_ecef2enu * dx_ecef;
        range = norm(enu);
        elev = asind(enu(3) / range);
        if elev >= elevation_mask
            vis_LEO_xyz = [vis_LEO_xyz; satXYZ];
            
            % 計算速度特徵
            abs_speed = norm(satVel); 
            line_of_sight_vec = dx_ecef / range; 
            radial_vel = dot(satVel', line_of_sight_vec); 
            
            distance_log = [distance_log; t_sim, 2, LEO_sats(k,1), range/1000, elev, abs_speed/1000, radial_vel/1000];
        end
    end
    
    %% 更新圖型位置
    set(h_meo_all, 'XData', MEO_sats(:,2), 'YData', MEO_sats(:,3), 'ZData', MEO_sats(:,4));
    set(h_leo_all, 'XData', LEO_sats(:,2), 'YData', LEO_sats(:,3), 'ZData', LEO_sats(:,4));
    
    if ~isempty(vis_MEO_xyz)
        set(h_meo_vis, 'XData', vis_MEO_xyz(:,1), 'YData', vis_MEO_xyz(:,2), 'ZData', vis_MEO_xyz(:,3));
    else
        set(h_meo_vis, 'XData', nan, 'YData', nan, 'ZData', nan);
    end
    
    if ~isempty(vis_LEO_xyz)
        set(h_leo_vis, 'XData', vis_LEO_xyz(:,1), 'YData', vis_LEO_xyz(:,2), 'ZData', vis_LEO_xyz(:,3));
    else
        set(h_leo_vis, 'XData', nan, 'YData', nan, 'ZData', nan);
    end
    
    title(sprintf('Constellations Animation (Time = %d s)', t_sim));
    drawnow;
    
    %% 獲取目前的 Figure 當下影格並寫入影片
    frame = getframe(fig);
    writeVideo(v, frame);
end

% 關閉影片並儲存
close(v);
disp(['動畫生成完畢，已儲存於當前目錄下: ', video_filename]);

%% 紀錄並輸出距離資料
% 轉換為 table 會更好觀看
T_dist = array2table(distance_log, 'VariableNames', {'Time_s', 'Constellation', 'Sat_ID', 'Distance_km', 'Elevation_deg', 'Abs_Speed_km_s', 'Radial_Vel_km_s'});
% 顯示資料集描述 (其中 1 代表 MEO, 2 代表 LEO)
save('distance_data.mat', 'T_dist');
disp('----------------- 可見衛星分析預覽 (前五筆) ---------------');
disp('  Constellation: 1=MEO, 2=LEO');
disp(head(T_dist, 5));
