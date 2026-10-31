%% 任务一：配电网24小时交流潮流
% 潘子岩，206221322。功率单位为MW/Mvar，电压单位为p.u.。
% 每个时段均从基准算例重新构造负荷，避免负荷系数连续累乘。
candidate_dirs = {fileparts(mfilename('fullpath')), pwd};
try
    candidate_dirs{end+1} = fileparts(matlab.desktop.editor.getActiveFilename);
catch
end
script_dir = '';
for k = 1:numel(candidate_dirs)
    if isfile(fullfile(candidate_dirs{k}, 'helpers', 'ess_live_setup.m'))
        script_dir = candidate_dirs{k};
        break
    end
end
assert(~isempty(script_dir), '作业目录中缺少helpers。');
addpath(fullfile(script_dir, 'helpers'), '-begin');
lesson = ess_live_setup();
assert(exist('runpf', 'file') == 2, '缺少MATPOWER函数runpf。');
export_figures = true;

%% 学号参数与设备参数
Stu_ID = 206221322;
Student_Name = '潘子岩';
XY = mod(Stu_ID, 100);
X_digit = floor(XY/10);
Y_digit = mod(XY, 10);
if Y_digit <= 3
    case_name = 'case_nongcun';
elseif Y_digit <= 6
    case_name = 'case_chengshi_A';
else
    case_name = 'case_kaifaqu_A';
end
if X_digit <= 2
    study_buses = [4 9 14];
elseif X_digit <= 5
    study_buses = [5 11 16];
else
    study_buses = [6 13 17];
end
load_multiplier = 1;
alpha = (1 + 0.002*XY)*load_multiplier;
P_pv_peak_MW = 0.8; % 每个指定节点的光伏装机功率
mpc_base = loadcase(fullfile(lesson.cases, [case_name '.m']));
profiles = load(fullfile(lesson.cases, 'profiles_24h.mat'));
T = profiles.T;
dt = 1; % h
load_curve_pu = profiles.load_curve_pu(:);
pv_curve_pu = profiles.pv_curve_pu(:);
pv_buses = study_buses;
N_bus = size(mpc_base.bus, 1);
assert(T == 24 && numel(load_curve_pu) == T && numel(pv_curve_pu) == T, ...
    '24小时曲线维度不一致。');

%% 时序潮流与全天损耗
% Pnet(i,t)=alpha*Pload(i,0)*load_curve(t)-Ppv(i,t)。
% 全天电能损耗等于逐时有功损耗乘以时间步长后求和，单位MWh。
[V_bus_24h, P_loss_24h, converged] = local_daily_powerflow( ...
    mpc_base, alpha, load_curve_pu, pv_curve_pu, pv_buses, P_pv_peak_MW);
[min_V, ix] = min(V_bus_24h(:));
[min_bus_row, min_hour] = ind2sub(size(V_bus_24h), ix);
min_bus = mpc_base.bus(min_bus_row, 1);
DailyLoss_MWh = sum(P_loss_24h)*dt;
Hourly = table((1:T)', min(V_bus_24h, [], 1)', P_loss_24h, ...
    'VariableNames', {'Hour', 'MinVoltage_pu', 'Loss_MW'});

%% 增大负荷系数后的午间与晚高峰比较
% 光伏装机与时序曲线保持相同，将个人负荷系数增大10%。
alpha_increased = alpha*1.10;
[V_increased, loss_increased] = local_daily_powerflow( ...
    mpc_base, alpha_increased, load_curve_pu, pv_curve_pu, pv_buses, P_pv_peak_MW);
compare_hours = [12; 19];
LoadComparison = table(compare_hours, ...
    min(V_bus_24h(:, compare_hours), [], 1)', ...
    min(V_increased(:, compare_hours), [], 1)', ...
    P_loss_24h(compare_hours), loss_increased(compare_hours), ...
    'VariableNames', {'Hour', 'BaseMinVoltage_pu', 'IncreasedMinVoltage_pu', ...
    'BaseLoss_MW', 'IncreasedLoss_MW'});

%% 全网节点电压时序分布、薄弱节点电压与网损
fig_voltage = figure('Color', 'w', 'Position', [80 80 1160 760]);
if isprop(fig_voltage, 'Theme'), theme(fig_voltage, 'light'); end
tiledlayout(2, 2, 'TileSpacing', 'compact', 'Padding', 'compact');
nexttile([1 2]);
imagesc(1:T, mpc_base.bus(:, 1), V_bus_24h);
set(gca, 'YDir', 'normal');
xlabel('时段 / h'); ylabel('节点编号');
title(sprintf('全网%d个节点的24小时电压分布', N_bus));
xticks([1 6 12 18 24]);
cb = colorbar; cb.Label.String = '电压 / p.u.';
hold on;
plot(min_hour, min_bus, 'wp', 'MarkerSize', 12, 'LineWidth', 1.5);
nexttile;
plot(1:T, V_bus_24h(min_bus_row, :), '-o', 'LineWidth', 1.5, 'MarkerSize', 3);
hold on;
plot(min_hour, min_V, 'ro', 'MarkerFaceColor', 'r', 'MarkerSize', 6);
yline(0.95, '--r'); yline(1.05, '--r');
xlabel('时段 / h'); ylabel('电压 / p.u.');
title(sprintf('薄弱节点%d：最低电压%.6f p.u.', min_bus, min_V));
xlim([1 T]); grid on; box on;
nexttile;
bar(1:T, P_loss_24h, 'FaceColor', [0.20 0.50 0.70]);
xlabel('时段 / h'); ylabel('有功损耗 / MW');
title(sprintf('逐时网损：全天电能损耗%.6f MWh', DailyLoss_MWh));
xlim([0.5 T+0.5]); grid on; box on;
sgtitle(sprintf('%s %d | 配电网时序潮流', Student_Name, Stu_ID));
set(findall(fig_voltage, '-property', 'FontName'), 'FontName', 'PingFang SC');
set(findall(fig_voltage, 'Type', 'axes'), 'FontSize', 11);

%% 标准结果与图表保存
Day1 = struct('StudentID', Stu_ID, 'StudentName', Student_Name, ...
    'Case', case_name, 'LoadMultiplier', alpha, 'StudyNodes', study_buses, ...
    'PVPeakPerBus_MW', P_pv_peak_MW, 'TimeStep_h', dt, ...
    'NodeIDs', mpc_base.bus(:, 1), 'MinVoltage', min_V, ...
    'MinVoltageNode', min_bus, 'MinVoltageHour', min_hour, ...
    'DailyLoss_MWh', DailyLoss_MWh, 'V_bus_24h', V_bus_24h, ...
    'P_loss_24h', P_loss_24h, 'Converged', converged, 'Hourly', Hourly, ...
    'IncreasedLoadMultiplier', alpha_increased, ...
    'IncreasedDailyLoss_MWh', sum(loss_increased)*dt, ...
    'IncreasedVoltage', V_increased, 'LoadComparison', LoadComparison);
summary_file = fullfile(script_dir, 'result_summary.mat');
if isfile(summary_file)
    save(summary_file, 'Day1', '-append');
else
    save(summary_file, 'Day1');
end
if export_figures
    ess_live_export(fig_voltage, script_dir, sprintf('Fig_Week1_Task1_%d', Stu_ID));
end
Lesson_Stats = struct('Lesson', 1, 'MinVoltage', min_V, ...
    'MinVoltageNode', min_bus, 'MinVoltageHour', min_hour, ...
    'DailyLoss_MWh', DailyLoss_MWh, 'AllPowerFlowsConverged', all(converged));
disp(struct2table(Lesson_Stats));
disp(LoadComparison);

function [V, losses, converged] = local_daily_powerflow(mpc_base, alpha, ...
        load_curve, pv_curve, pv_buses, pv_peak)
T = numel(load_curve);
V = zeros(size(mpc_base.bus, 1), T);
losses = zeros(T, 1);
converged = false(T, 1);
[present, pv_rows] = ismember(pv_buses, mpc_base.bus(:, 1));
assert(all(present), '光伏节点不在算例中。');
mpopt = mpoption('verbose', 0, 'out.all', 0);
for t = 1:T
    mpc_t = mpc_base;
    mpc_t.bus(:, 3) = mpc_base.bus(:, 3)*alpha*load_curve(t);
    mpc_t.bus(:, 4) = mpc_base.bus(:, 4)*alpha*load_curve(t);
    mpc_t.bus(pv_rows, 3) = mpc_t.bus(pv_rows, 3) - pv_peak*pv_curve(t);
    pf = runpf(mpc_t, mpopt);
    converged(t) = pf.success == 1;
    assert(converged(t), '第%d时段交流潮流未收敛。', t);
    V(:, t) = pf.bus(:, 8);
    losses(t) = sum(real(get_losses(pf)));
end
end
