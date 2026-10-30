%% ========================================================================
%  第一周 任务一：24 小时交流潮流与节点电压时序诊断
%  姓名：刘宇成      学号：208231323      班级：储能231
%  算例：case_nongcun（49 节点农村配电网，12.66 kV / 100 MVA）
%  学号映射：XY = 23  ->  alpha = 1 + 0.002*23 = 1.046
%            个位 3  ->  农村配电网 case_nongcun
%            十位 2  ->  模型 A（最大化新能源消纳），接入节点 {4, 9, 14}
%  计算条件：三个光伏节点各接入 0.8 MW 固定出力光伏，不配置储能（基态对照）
%  交付：Fig_Week1_Task1_208231323.png / .pdf / .fig、result_summary.mat
%% ========================================================================
clear; clc; close all;

%% 1. 课程资源路径（换电脑时只需修改这一行）
mat_dir = "C:\Users\Administrator\Desktop\matlab\ESS-Course-Materials-main\ESS-Course-Materials-main";
if ~isfolder(mat_dir)
    mat_dir = uigetdir(pwd, '请选择本机 ESS-Course-Materials 仓库根目录');
end
addpath(fullfile(mat_dir, 'cases'));
out_dir = fileparts(mfilename('fullpath'));
if isempty(out_dir)
    out_dir = pwd;
end

%% 2. 学号映射与场景参数
Stu_ID  = 208231323;
XY      = mod(Stu_ID, 100);
X_digit = floor(XY / 10);
Y_digit = mod(XY, 10);
alpha   = 1 + 0.002 * XY;          % = 1.046

if ismember(Y_digit, [0 1 2 3])
    case_name = 'case_nongcun';
elseif ismember(Y_digit, [4 5 6])
    case_name = 'case_chengshi_A';
else
    case_name = 'case_kaifaqu_A';
end

if ismember(X_digit, [0 1 2])
    pv_buses = [4 9 14];  model_type = 'A';
elseif ismember(X_digit, [3 4 5])
    pv_buses = [5 11 16]; model_type = 'B';
else
    pv_buses = [6 13 17]; model_type = 'C';
end

P_pv_peak_MW = 0.8;                 % 单个光伏节点装机（任务一固定出力）
dt = 1;

profiles     = load(fullfile(mat_dir, 'cases', 'profiles_24h.mat'));
T            = profiles.T;
load_curve   = profiles.load_curve_pu;
pv_curve     = profiles.pv_curve_pu;
price_MWh    = profiles.price_MWh;

mpc_base = loadcase(case_name);
N_bus    = size(mpc_base.bus, 1);

fprintf('学号 %d | 算例 %s | 模型 %s | alpha = %.3f | 光伏节点 %s\n', ...
    Stu_ID, case_name, model_type, alpha, mat2str(pv_buses));

%% 3. 24 小时交流潮流（MATPOWER runpf）
mpopt      = mpoption('verbose', 0, 'out.all', 0);
V_bus_24h  = zeros(N_bus, T);
P_loss_24h = zeros(T, 1);

for t = 1:T
    mpc_t = mpc_base;
    % 全网有功/无功负荷按 alpha 与典型日曲线缩放
    mpc_t.bus(:, 3) = mpc_base.bus(:, 3) * alpha * load_curve(t);
    mpc_t.bus(:, 4) = mpc_base.bus(:, 4) * alpha * load_curve(t);
    % 光伏出力从接入节点负荷中扣除
    mpc_t.bus(pv_buses, 3) = mpc_t.bus(pv_buses, 3) - P_pv_peak_MW * pv_curve(t);

    res = runpf(mpc_t, mpopt);
    assert(res.success == 1, '第 %d 时段交流潮流未收敛。', t);

    V_bus_24h(:, t)  = res.bus(:, 8);
    P_loss_24h(t)    = sum(real(get_losses(res)));
end

%% 4. 全天最低节点电压与全天电能损耗
[min_V, idx]      = min(V_bus_24h(:));
[min_bus, min_hr] = ind2sub(size(V_bus_24h), idx);
DailyLoss_MWh     = sum(P_loss_24h) * dt;
[Vmax, idx_max]   = max(V_bus_24h(:));
[max_bus, max_hr] = ind2sub(size(V_bus_24h), idx_max);

fprintf('\n================ 任务一：24 小时基态潮流诊断 ================\n');
fprintf('全天最低节点电压 : %.4f p.u.（节点 %d，第 %d 小时）\n', min_V, min_bus, min_hr);
fprintf('全天最高节点电压 : %.4f p.u.（节点 %d，第 %d 小时）\n', Vmax, max_bus, max_hr);
fprintf('全天电能损耗     : %.4f MWh\n', DailyLoss_MWh);
fprintf('电压合格率(<0.95): %.2f %%\n', 100 * mean(V_bus_24h(:) >= 0.95));
fprintf('============================================================\n');

%% 5. 思考练习：增大负荷系数 alpha 后重新计算
% 保持 alpha 的学号基数不变，附加倍率取 1.10（即 alpha2 = 1.046*1.10 = 1.1506）
load_multiplier = 1.10;
alpha2 = alpha * load_multiplier;
V_bus_24h_2 = zeros(N_bus, T);
P_loss_24h_2 = zeros(T, 1);

for t = 1:T
    mpc_t = mpc_base;
    mpc_t.bus(:, 3) = mpc_base.bus(:, 3) * alpha2 * load_curve(t);
    mpc_t.bus(:, 4) = mpc_base.bus(:, 4) * alpha2 * load_curve(t);
    mpc_t.bus(pv_buses, 3) = mpc_t.bus(pv_buses, 3) - P_pv_peak_MW * pv_curve(t);
    res = runpf(mpc_t, mpopt);
    assert(res.success == 1, '第 %d 时段交流潮流未收敛（alpha2）。', t);
    V_bus_24h_2(:, t)  = res.bus(:, 8);
    P_loss_24h_2(t)    = sum(real(get_losses(res)));
end

hr_midday = 12;   % 午间（光伏出力大、负荷平稳）
hr_evening = 19;  % 晚高峰（光伏已退出、负荷高）

cmp = table( ...
    ["午间 12:00"; "晚高峰 19:00"], ...
    [min(V_bus_24h(:, hr_midday));   min(V_bus_24h(:, hr_evening))], ...
    [min(V_bus_24h_2(:, hr_midday)); min(V_bus_24h_2(:, hr_evening))], ...
    [P_loss_24h(hr_midday);  P_loss_24h(hr_evening)], ...
    [P_loss_24h_2(hr_midday); P_loss_24h_2(hr_evening)], ...
    'VariableNames', {'TimeSection', 'Vmin_pu', 'Vmin_pu_alpha11', ...
                      'Loss_MWh', 'Loss_MWh_alpha11'});
disp('--- 增大负荷系数 alpha 前后的对比 ---');
disp(cmp);

%% 6. 绘图：全网节点电压时序分布
set(groot, 'defaultAxesFontName', 'Times New Roman');
set(groot, 'defaultTextFontName', 'Times New Roman');

fig = figure('Name', '第一周任务一：24 小时节点电压时序分布', ...
    'Color', 'w', 'Position', [80, 60, 820, 860]);
if isprop(fig, 'Theme'), theme(fig, 'light'); end

% (a) 全节点电压曲线族
subplot(3, 1, 1);
hold on;
plot(1:T, V_bus_24h', '-', 'Color', [0.65, 0.68, 0.72], 'LineWidth', 0.7);
h_min = plot(1:T, V_bus_24h(min_bus, :), '-', 'Color', [0.85, 0.20, 0.15], 'LineWidth', 1.8);
yline(0.95, '--k', 'LineWidth', 1.0);
yline(1.05, '--k', 'LineWidth', 1.0);
plot(min_hr, min_V, 'p', 'MarkerSize', 9, 'MarkerFaceColor', [0.85, 0.20, 0.15], ...
    'MarkerEdgeColor', 'k');
text(min_hr + 0.4, min_V - 0.004, sprintf('最低 %.4f p.u.\\newline节点 %d / %d:00', ...
    min_V, min_bus, min_hr), 'FontSize', 9, 'Color', [0.6, 0.1, 0.1], 'VerticalAlignment', 'top');
xlim([1, T]); ylim([0.93, 1.065]);
set(gca, 'Box', 'on', 'TickDir', 'in', 'XTick', 0:4:24, 'GridLineStyle', ':', 'XGrid', 'on', 'YGrid', 'on', ...
    'Color', 'w', 'XColor', 'k', 'YColor', 'k');
xlabel('时间 {\itt} / h', 'FontSize', 10.5);
ylabel('节点电压 {\itV} / p.u.', 'FontSize', 10.5);
title('(a) 全网 49 个节点电压时序曲线（灰线）与最低电压节点（红线）', ...
    'FontSize', 11, 'FontWeight', 'normal');
legend([h_min], {sprintf('节点 %d（全天最低）', min_bus)}, 'Location', 'southeast', 'FontSize', 9);

% (b) 节点-时间电压分布热图
subplot(3, 1, 2);
imagesc(1:T, 1:N_bus, V_bus_24h);
colormap(gca, parula);
cb = colorbar;
cb.Label.String = '节点电压 / p.u.';
caxis([min(V_bus_24h(:)), max(V_bus_24h(:))]);
set(gca, 'YDir', 'normal', 'Box', 'on', 'TickDir', 'in', 'XTick', 0:4:24, ...
    'Color', 'w', 'XColor', 'k', 'YColor', 'k');
xlabel('时间 {\itt} / h', 'FontSize', 10.5);
ylabel('节点编号 {\iti}', 'FontSize', 10.5);
title('(b) 全网节点电压 {V_{i,t}} 时序分布（颜色越深电压越低）', ...
    'FontSize', 11, 'FontWeight', 'normal');

% (c) alpha 增大前后的最低电压对比
subplot(3, 1, 3);
b = bar([cmp.Vmin_pu, cmp.Vmin_pu_alpha11], 'grouped');
b(1).FaceColor = [0.20, 0.45, 0.70];
b(2).FaceColor = [0.85, 0.45, 0.20];
hold on;
yline(0.95, '--k', 'LineWidth', 1.0);
set(gca, 'Box', 'on', 'TickDir', 'in', 'XTickLabel', {'午间 12:00', '晚高峰 19:00'}, ...
    'Color', 'w', 'XColor', 'k', 'YColor', 'k');
ylim([0.88, 1.00]);
ylabel('全网最低电压 / p.u.', 'FontSize', 10.5);
title(sprintf('(c) 负荷系数增大前后对比（\\alpha = %.3f → %.4f，附加倍率 %.2f）', ...
    alpha, alpha2, load_multiplier), 'FontSize', 11, 'FontWeight', 'normal');
legend({sprintf('\\alpha = %.3f', alpha), sprintf('\\alpha = %.4f', alpha2)}, ...
    'Location', 'northeast', 'FontSize', 9);
grid on;
for k = 1:2
    text(k - 0.15, cmp.Vmin_pu(k) - 0.012, sprintf('%.4f', cmp.Vmin_pu(k)), ...
        'HorizontalAlignment', 'center', 'FontSize', 8.5);
    text(k + 0.15, cmp.Vmin_pu_alpha11(k) - 0.012, sprintf('%.4f', cmp.Vmin_pu_alpha11(k)), ...
        'HorizontalAlignment', 'center', 'FontSize', 8.5);
end

%% 7. 导出白底 600 dpi PNG、矢量 PDF 与 FIG 图源
exportgraphics(fig, fullfile(out_dir, sprintf('Fig_Week1_Task1_%d.png', Stu_ID)), ...
    'Resolution', 600, 'BackgroundColor', 'white');
exportgraphics(fig, fullfile(out_dir, sprintf('Fig_Week1_Task1_%d.pdf', Stu_ID)), ...
    'ContentType', 'vector', 'BackgroundColor', 'white');
savefig(fig, fullfile(out_dir, sprintf('Fig_Week1_Task1_%d.fig', Stu_ID)));

%% 8. 写入标准化结果结构体 result_summary.mat
res_file = fullfile(out_dir, 'result_summary.mat');
if isfile(res_file)
    S = load(res_file);
    Result = S.Result;
else
    Result = struct();
end
Result.StuID      = Stu_ID;
Result.Name       = 'LiuYucheng';
Result.alpha      = alpha;
Result.case_name  = case_name;
Result.model_type = model_type;
Result.Task1 = struct( ...
    'P_pv_peak_MW',   P_pv_peak_MW, ...
    'pv_buses',       pv_buses, ...
    'MinVoltage_pu',  min_V, ...
    'MinVoltageBus',  min_bus, ...
    'MinVoltageHour', min_hr, ...
    'MaxVoltage_pu',  Vmax, ...
    'DailyLoss_MWh',  DailyLoss_MWh, ...
    'AlphaSweep',     struct('multiplier', load_multiplier, 'alpha2', alpha2, ...
                             'Vmin_midday_alpha2',   min(V_bus_24h_2(:, hr_midday)), ...
                             'Vmin_evening_alpha2',  min(V_bus_24h_2(:, hr_evening)), ...
                             'Loss_midday_alpha2',   P_loss_24h_2(hr_midday), ...
                             'Loss_evening_alpha2',  P_loss_24h_2(hr_evening), ...
                             'DailyLoss_alpha2_MWh', sum(P_loss_24h_2)) );
save(res_file, 'Result');
fprintf('结果已保存：%s\n', res_file);
