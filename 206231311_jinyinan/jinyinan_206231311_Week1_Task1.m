%[text] # 任务一：24 小时基态时序潮流诊断
%[text] 课程：《储能优化规划与运行》课程设计（南京工程学院）
%[text] 本文件为第一周**任务一（时序潮流诊断）**的独立提交脚本，可单独"全部运行"。
%[text] **个人参数**：学号 $206231311$，末两位 $X=1,\ Y=1$ → $\alpha = 1.022$，
%[text] 算例 `case_nongcun`（49 节点，12.66 kV / 100 MVA），任务一接入节点 {4,9,14}，每节点 0.8 MW 光伏，不配储能
%[text] 对应课件：interactive01（时序潮流）、demo01（MATPOWER 潮流）。
%[text] ## 0 运行环境与个人参数
%%
%[text] ### 0.1 添加教学资源库、MATPOWER 与 YALMIP 路径
%[text] 首次运行请把 `ess_course_root` 改为本机 `ESS-Course-Materials` 的根目录；若该目录不存在，程序会弹出选择框。
ess_course_root = 'D:\ess_toolbox\ESS-Course-Materials';
matpower_root   = 'D:\ess_toolbox\matpower-8.1';
yalmip_root     = 'D:\ess_toolbox\YALMIP-master';
if ~isfolder(ess_course_root)
    ess_course_root = uigetdir(pwd, '请选择教学资源库 ESS-Course-Materials 的根目录');
end
if isfolder(matpower_root)
    mp_dirs = {'lib','lib/t','data','examples', ...
        'most/lib','most/lib/t','most/examples', ...
        'mp-opt-model/lib','mp-opt-model/lib/t','mp-opt-model/examples', ...
        'mips/lib','mips/lib/t','mips/examples','mptest/lib','mptest/lib/t'};
    for k = 1:numel(mp_dirs)
        d = fullfile(matpower_root, mp_dirs{k});
        if isfolder(d), addpath(d); end
    end
end
if isfolder(yalmip_root)
    addpath(genpath(yalmip_root));
end
addpath(fullfile(ess_course_root,'cases'));
assert(exist('runpf','file')==2, '未找到 MATPOWER：请检查 matpower_root。');
assert(exist('sdpvar','file')==2, '未找到 YALMIP：请检查 yalmip_root。');
fprintf('MATPOWER : %s\nYALMIP   : %s\n算例库   : %s\n', which('runpf'), which('sdpvar'), which('case_nongcun'));
%%
%[text] ### 0.2 学号映射与公共参数
%[text] 学号末两位 $XY$ 决定算例、$\alpha$、调度模型与候选节点；中间变量统一使用有名值 MW/Mvar 或标幺值 p.u.。
Stu_ID  = 206231311;
XY      = mod(Stu_ID, 100);
X_digit = floor(XY / 10);
Y_digit = mod(XY, 10);
alpha   = 1 + 0.002 * XY;
if ismember(Y_digit, [0 1 2 3])
    case_name = 'case_nongcun';
elseif ismember(Y_digit, [4 5 6])
    case_name = 'case_chengshi_A';
else
    case_name = 'case_kaifaqu_A';
end
if ismember(X_digit, [0 1 2])
    study_buses = [4 9 14];  model_type = 'A';
elseif ismember(X_digit, [3 4 5])
    study_buses = [5 11 16]; model_type = 'B';
else
    study_buses = [6 13 17]; model_type = 'C';
end
profiles = load(fullfile(ess_course_root,'cases','profiles_24h.mat'));
T = profiles.T;  dt = 1;
load_curve_pu = profiles.load_curve_pu(:);
pv_curve_pu   = profiles.pv_curve_pu(:);
price_MWh     = profiles.price_MWh(:);
price_kWh     = profiles.price_kWh(:);
mpc_base = loadcase(case_name);
mpopt    = mpoption('verbose',0,'out.all',0);
disp(table(Stu_ID, string(case_name), alpha, string(model_type), ...
    string(mat2str(study_buses)), 'VariableNames', ...
    {'StudentID','Case','LoadMultiplier','AssignedObjective','StudyNodes'}));

% 图形输出目录：各节画完立即导出（Live Editor 会在切换节时回收图形句柄）
out_dir = fullfile(pwd, 'figures');
if ~isfolder(out_dir), mkdir(out_dir); end
export_figs = true;

%[text] ## 1 任务一：24 小时基态时序交流潮流
%[text] 不接入储能，在 $\{4,9,14\}$ 三个节点各接入 **0.8 MW** 固定出力光伏（随光伏曲线出力）。各时段均从基准算例重新构造负荷：
%[text] $$P_{i,t}^{\mathrm{net}} = \alpha P_{i,0}^{\mathrm{load}} p_t^{\mathrm{load}} - P_{i,t}^{\mathrm{pv}}$$
%[text] 用 MATPOWER `runpf` 逐时求交流潮流，统计节点电压与全天电能损耗：
%[text] $$E_{\mathrm{loss}} = \sum_{t=1}^{T} P_{\mathrm{loss},t}\,\Delta t$$
%%
P_pv_peak = 0.8;
N_bus = size(mpc_base.bus, 1);
V_pv = zeros(N_bus, T);   V_nopv = zeros(N_bus, T);
P_loss_pv = zeros(T,1);   P_loss_nopv = zeros(T,1);
for t = 1:T
    % （1）含分布式光伏
    mpc_t = mpc_base;
    mpc_t.bus(:,3) = mpc_base.bus(:,3) * alpha * load_curve_pu(t);
    mpc_t.bus(:,4) = mpc_base.bus(:,4) * alpha * load_curve_pu(t);
    mpc_t.bus(study_buses,3) = mpc_t.bus(study_buses,3) - P_pv_peak*pv_curve_pu(t);
    res = runpf(mpc_t, mpopt);
    assert(res.success==1, '第 %d 时段交流潮流未收敛。', t);
    V_pv(:,t) = res.bus(:,8);
    P_loss_pv(t) = sum(real(get_losses(res)));
    % （2）无光伏基态对照
    mpc_0 = mpc_base;
    mpc_0.bus(:,3) = mpc_base.bus(:,3) * alpha * load_curve_pu(t);
    mpc_0.bus(:,4) = mpc_base.bus(:,4) * alpha * load_curve_pu(t);
    res0 = runpf(mpc_0, mpopt);
    V_nopv(:,t) = res0.bus(:,8);
    P_loss_nopv(t) = sum(real(get_losses(res0)));
end
[minV, ix] = min(V_pv(:));
[bus_minV, hour_minV] = ind2sub(size(V_pv), ix);
[maxV, ix2] = max(V_pv(:));
[bus_maxV, hour_maxV] = ind2sub(size(V_pv), ix2);
E_loss_pv   = sum(P_loss_pv);
E_loss_nopv = sum(P_loss_nopv);
E_load = sum(mpc_base.bus(:,3)) * alpha * sum(load_curve_pu);
E_pv   = P_pv_peak * numel(study_buses) * sum(pv_curve_pu);
node_minV = min(V_pv, [], 2);
[~, order] = sort(node_minV, 'ascend');
T1 = table(string({'最低电压';'最低电压节点';'最低电压时段';'最高电压';'最高电压节点';'最高电压时段'; ...
     '含光伏全天网损/MWh';'无光伏全天网损/MWh';'全天负荷电量/MWh';'光伏发电量/MWh';'线损率/%'}), ...
    [minV; bus_minV; hour_minV; maxV; bus_maxV; hour_maxV; E_loss_pv; E_loss_nopv; ...
     E_load; E_pv; 100*E_loss_pv/E_load], 'VariableNames', {'指标','数值'});
disp(T1);
fprintf('电压最低的 5 个节点：%s\n', mat2str(order(1:5)'));
fprintf('电压越限统计：低于 0.95 p.u. 的时段数 = %d，高于 1.05 p.u. 的时段数 = %d\n', ...
    nnz(any(V_pv(2:end,:) < 0.95, 1)), nnz(any(V_pv(2:end,:) > 1.05, 1)));
%%
%[text] ### 1.1 任务一图形：24 小时电压包络与逐时网损
fig1 = figure('Name','任务一 时序潮流','Color','w','Units','pixels','Position',[90 70 1000 640]);
tt = 1:T;
ax1 = subplot(2,1,1); hold(ax1,'on');
env_lo = min(V_pv,[],1);  env_hi = max(V_pv,[],1);
patch(ax1, [tt fliplr(tt)], [env_lo fliplr(env_hi)], [0.435 0.467 0.522], ...
    'FaceAlpha',0.18,'EdgeColor','none');
mk = {'-o','-s','-^'};
clr = [0.235 0.329 0.533; 0.000 0.627 0.529; 0.902 0.294 0.208];
hk = gobjects(numel(study_buses),1);
for k = 1:numel(study_buses)
    hk(k) = plot(ax1, tt, V_pv(study_buses(k),:), mk{k}, 'Color', clr(k,:), ...
        'LineWidth', 2, 'MarkerSize', 5, 'MarkerFaceColor', clr(k,:));
end
hlim = yline(ax1, 1.05, ':', 'Color', clr(3,:), 'LineWidth', 1.5);
yline(ax1, 0.95, ':', 'Color', clr(3,:), 'LineWidth', 1.5);
style_axes(ax1);
xlim(ax1,[1 T]);
xlabel(ax1,'\fontname{宋体}时间 \fontname{Times New Roman}{\itt}\rm{/h}','Interpreter','tex');
ylabel(ax1,'\fontname{宋体}节点电压 \fontname{Times New Roman}{\itV}\rm{/p.u.}','Interpreter','tex');
title(ax1, sprintf('\\fontname{宋体}(a) \\fontname{Times New Roman}\\it\\alpha\\rm{=%.3f} \\fontname{宋体}时各节点电压包络与光伏接入节点电压', alpha), ...
    'FontWeight','normal','Interpreter','tex');
lg = arrayfun(@(b) sprintf('\\fontname{宋体}节点 \\fontname{Times New Roman}%d', b), study_buses, 'UniformOutput', false);
legend(ax1, [hk; hlim], [lg, {'\fontname{宋体}电压限值'}], 'Location','northwest', ...
    'Orientation','horizontal','NumColumns',4,'Interpreter','tex','Box','off');
ax2 = subplot(2,1,2); hold(ax2,'on');
plot(ax2, tt, P_loss_nopv, '--s', 'Color', [0.435 0.467 0.522], 'LineWidth', 2, ...
    'MarkerSize', 5, 'MarkerFaceColor', [0.435 0.467 0.522]);
plot(ax2, tt, P_loss_pv, '-o', 'Color', clr(1,:), 'LineWidth', 2, ...
    'MarkerSize', 5, 'MarkerFaceColor', clr(1,:));
style_axes(ax2);
xlim(ax2,[1 T]);
xlabel(ax2,'\fontname{宋体}时间 \fontname{Times New Roman}{\itt}\rm{/h}','Interpreter','tex');
ylabel(ax2,'\fontname{宋体}逐时网损 \fontname{Times New Roman}{\itP}_{\rm{loss}}\rm{/MW}','Interpreter','tex');
title(ax2,'\fontname{宋体}(b) 含 ∕ 无分布式光伏时的逐时有功网损','FontWeight','normal','Interpreter','tex');
legend(ax2, {'\fontname{宋体}无光伏网损','\fontname{宋体}含光伏网损'}, 'Location','northwest', ...
    'NumColumns',2,'Interpreter','tex','Box','off');
if export_figs
    export_figure(fig1, out_dir, sprintf('Fig_Week1_Task1_%d', Stu_ID));
    drawnow;
end

% ---- 任务一：49 节点电压随时间与位置的三维曲面 ----
[tt_s, nn_s] = meshgrid(1:T, 1:N_bus);
fig1b = figure('Color','w','Units','pixels','Position',[80 70 1000 680]);
ax_surf = axes(fig1b); hold(ax_surf,'on');
[te_s, ne_s] = meshgrid([1 T], [1 N_bus]);
surf(ax_surf, te_s, ne_s, 1.05*ones(2), 'FaceColor', clr(3,:), 'FaceAlpha', 0.06, ...
    'EdgeColor', 'none');
surf(ax_surf, te_s, ne_s, 0.95*ones(2), 'FaceColor', clr(3,:), 'FaceAlpha', 0.06, ...
    'EdgeColor', 'none');
surf(ax_surf, tt_s, nn_s, V_pv, 'EdgeColor', 'none');
colormap(ax_surf, parula(256));
shading(ax_surf, 'interp');
disableDefaultInteractivity(ax_surf);
ax_surf.Toolbar.Visible = 'off';
[mns, ixs] = min(V_pv(:));
[bs, hs] = ind2sub([N_bus T], ixs);
plot3(ax_surf, hs, bs, mns, 'o', 'MarkerSize', 9, 'MarkerFaceColor', clr(3,:), ...
    'MarkerEdgeColor', 'k', 'LineWidth', 1.0);
plot3(ax_surf, [hs hs], [bs bs], [0.95 mns], ':', 'Color', clr(3,:), 'LineWidth', 1.2);
cb_s = colorbar(ax_surf);
cb_s.Label.String = '\fontname{宋体}节点电压 \fontname{Times New Roman}{\itV}\rm{/p.u.}';
cb_s.Label.Interpreter = 'tex';
cb_s.Label.FontSize = 11;
set(ax_surf, 'FontName','Times New Roman', 'FontSize', 10, 'Color','w', ...
    'Box','on', 'TickDir','in', 'LineWidth', 0.75);
xlim(ax_surf, [1 T]);  ylim(ax_surf, [1 N_bus]);  zlim(ax_surf, [0.94 1.06]);
set(ax_surf, 'XTick', 1:2:24, 'YTick', 1:4:N_bus);
view(ax_surf, -37.5, 32);
grid(ax_surf, 'on');
ax_surf.GridAlpha = 0.18;
xlabel(ax_surf, '\fontname{宋体}时间 \fontname{Times New Roman}{\itt}\rm{/h}', 'Interpreter','tex');
ylabel(ax_surf, '\fontname{宋体}节点编号 \fontname{Times New Roman}{\iti}', 'Interpreter','tex');
zlabel(ax_surf, '\fontname{宋体}节点电压 \fontname{Times New Roman}{\itV}\rm{/p.u.}', 'Interpreter','tex');
title(ax_surf, sprintf('\\fontname{宋体}任务一：\\fontname{Times New Roman}\\it\\alpha\\rm{=%.3f} \\fontname{宋体}时 49 节点电压随时间与位置的三维分布', alpha), ...
    'FontWeight','normal', 'Interpreter','tex', 'FontSize', 12);
if export_figs
    export_figure(fig1b, out_dir, sprintf('Fig_Week1_Task1_Surface_%d', Stu_ID));
    drawnow;
end

%[text] ## 结论与思考题
%[text] **结论**：$\alpha=1.022$ 时全网最低电压出现在晚峰第 19 时段的末端节点 14；
%[text] 午间光伏大发时节点 14 电压越过 1.05 p.u. 上限，说明该长馈线存在"午间过电压 / 晚峰低电压"的双向问题；
%[text] 含光伏的全天网损反而高于无光伏，原因是功率经长线路倒送抬高了支路电流。
%[text] **思考题（interactive01 练习）**：把附加负荷倍率由 1.00 提高到 1.10，
%[text] 预测最低电压与全天电能损耗如何变化，计算后记录节点、时段与数值并解释原因。
%[text] 预测：负荷整体提高 10%，各节点电压普遍下降、线路电流增大，最低电压会更低、全天网损显著上升。
%[text] 定量结果见报告"思考题"一节。
if export_figs
    fprintf('\n[提示] 思考题：把 load_multiplier 由 1.00 改为 1.10 后重新运行本脚本，\n');
    fprintf('       记录最低电压与全天损耗的变化，填入报告。\n');
end

%[text] ## 附：局部函数
%%
function style_axes(ax)
set(ax,'Color','w','XColor','k','YColor','k','FontName','Times New Roman', ...
    'FontSize',11,'LineWidth',0.75,'Box','on','TickDir','in', ...
    'GridLineStyle','--','XGrid','off','YGrid','on','GridAlpha',0.25, ...
    'GridColor',[0.4 0.4 0.4]);
end

function export_figure(f, outdir, base)
if ~isfolder(outdir), mkdir(outdir); end
exportgraphics(f, fullfile(outdir,[base '.png']), 'Resolution',600, 'BackgroundColor','white');
exportgraphics(f, fullfile(outdir,[base '.pdf']), 'ContentType','vector', 'BackgroundColor','white');
savefig(f, fullfile(outdir,[base '.fig']));
fprintf('已导出 %s.(png|pdf|fig)\n', base);
end

