function Summary=week1_export_analysis(folder,Student,Runs,Comparison,alpha)
% 第一周补充图形及可核查数据。所有输入均来自实际求解；不修剪数值残差。
id=Student.ID; assigned=Runs.A;d=assigned.Data;c=assigned.Check;
T=size(d.SoC,2);nb=size(d.mpc.bus,1);nl=size(d.mpc.branch,1);
colors=[60 84 136;0 160 135;230 75 53]/255;
% 同一负荷、同一1.2 MW/节点光伏、无储能且全部接纳光伏的交流基准。
base_v=zeros(nb,T);base_loss=zeros(1,T);base_grid=zeros(1,T);
opts=mpoption('verbose',0,'out.all',0,'pf.tol',1e-10);
for t=1:T
    ac=d.mpc;ac.bus(:,3)=d.PloadMW(:,t);ac.bus(:,4)=d.QloadMvar(:,t);
    ac.bus(d.pv_buses,3)=ac.bus(d.pv_buses,3)-d.PpvMaxMW(:,t);
    r=runpf(ac,opts);assert(r.success==1,'无储能基准第%d时段不收敛。',t);
    base_v(:,t)=r.bus(:,8);base_loss(t)=sum(real(get_losses(r)));base_grid(t)=sum(r.gen(:,2));
end
Baseline=struct('Description','同一1.2 MW/节点光伏、无储能且全额接纳的交流基准',...
    'Voltage',base_v,'LossMW',base_loss,'GridMW',base_grid,'Loss_MWh',sum(base_loss)*d.dt,...
    'GridCost_Yuan',sum(base_grid(:).*d.price_MWh(:))*d.dt,...
    'MinVoltage_pu',min(base_v,[],'all'),'MaxVoltage_pu',max(base_v,[],'all'));
[~,weak_bus]=min(min(base_v,[],2));
[~,ix]=min(assigned.VAC(:));[min_bus,min_hour]=ind2sub([nb T],ix);

%% 每个节点的充电与放电功率，分别绘制以检查互斥状态。
f=newfig('第一周：逐节点充电与放电',1000,800);
tiledlayout(3,1,'TileSpacing','compact','Padding','compact');
for i=1:numel(d.ess_buses)
    nexttile;hold on;
    stairs(1:T,d.PchMW(i,:),'--','Color',colors(1,:),'LineWidth',2);
    stairs(1:T,d.PdisMW(i,:),'-','Color',colors(2,:),'LineWidth',2);
    title(sprintf('节点 %d',d.ess_buses(i)),'FontName','宋体');xlim([1 T]);ylim([-.04 1.65]);
    ylabel('\fontname{宋体}功率 \fontname{Times New Roman}{\itP}/MW');
    if i==1,legend({'充电','放电'},'FontName','宋体','Orientation','horizontal','Location','northoutside');end
end
xlabel('\fontname{宋体}时间 \fontname{Times New Roman}{\itt}/h');
finish(f,folder,sprintf('Fig_Week1_ChargeDischarge_%d',id));

%% 薄弱节点全天电压，以及本人方案最小电压时段的全网电压曲线。
f=newfig('第一周：节点电压与交流校验',1100,480);
tiledlayout(1,2,'TileSpacing','compact','Padding','compact');nexttile;hold on;
plot(1:T,base_v(weak_bus,:),'--','Color',[.44 .47 .52],'LineWidth',2);
plot(1:T,sqrt(d.U(weak_bus,:)),'-s','Color',colors(1,:),'MarkerIndices',1:3:T,'LineWidth',2);
plot(1:T,assigned.VAC(weak_bus,:),'-o','Color',colors(2,:),'MarkerIndices',2:3:T,'LineWidth',1.6);
title(sprintf('薄弱节点 %d 的全天电压',weak_bus),'FontName','宋体');xlim([1 T]);
xlabel('\fontname{宋体}时间 \fontname{Times New Roman}{\itt}/h');
ylabel('\fontname{宋体}电压幅值 \fontname{Times New Roman}{\itV}/p.u.');
legend({'无储能交流基准','MISOCP模型','配置后交流潮流'},'FontName','宋体','Location','southwest');
nexttile;hold on;
plot(1:nb,base_v(:,min_hour),'--','Color',[.44 .47 .52],'LineWidth',2);
plot(1:nb,sqrt(d.U(:,min_hour)),'-s','Color',colors(1,:),'LineWidth',2,'MarkerSize',4);
plot(1:nb,assigned.VAC(:,min_hour),'-o','Color',colors(2,:),'LineWidth',1.6,'MarkerSize',4);
title(sprintf('第 %d 时段的节点电压',min_hour),'FontName','宋体');xlim([1 nb]);
xlabel('节点编号','FontName','宋体');ylabel('\fontname{宋体}电压幅值 \fontname{Times New Roman}{\itV}/p.u.');
finish(f,folder,sprintf('Fig_Week1_Voltage_%d',id));

%% 全节点、全时段的交流电压及全支路、全时段的锥松弛间隙。
f=newfig('第一周：全网校验',1050,480);
tiledlayout(1,2,'TileSpacing','compact','Padding','compact');
nexttile;imagesc(1:T,1:nb,assigned.VAC);axis xy;colormap(parula);
cb=colorbar;cb.Label.String='电压 / p.u.';
title('全网、全天的交流潮流电压','FontName','宋体');
xlabel('时段','FontName','宋体');ylabel('节点编号','FontName','宋体');
nexttile;gap=abs(d.U(d.mpc.branch(:,1),:).*d.L-d.P.^2-d.Q.^2);
imagesc(1:T,1:nl,gap);axis xy;cb=colorbar;cb.Label.String='松弛间隙 / p.u.';
title(sprintf('最大锥松弛间隙 %.2e',c.MaxConeGap),'FontName','宋体');
xlabel('时段','FontName','宋体');ylabel('支路编号','FontName','宋体');
finish(f,folder,sprintf('Fig_Week1_Validation_%d',id));

%% 不同目标比较共同物理指标；不比较量纲不同的目标函数值的大小。
f=newfig('第一周：目标A/B/C比较',1000,720);
tiledlayout(2,2,'TileSpacing','compact','Padding','compact');
nexttile;bar(categorical({'A','B','C'}),Comparison.Curtailment_MWh,'FaceColor',colors(1,:));
title('弃光电量','FontName','宋体');ylabel('电量 / MWh','FontName','宋体');
nexttile;bar(categorical({'A','B','C'}),[Comparison.LineLoss_MWh Comparison.ACLineLoss_MWh]);
title('模型与交流潮流网损','FontName','宋体');ylabel('电量 / MWh','FontName','宋体');
legend({'模型','交流潮流'},'FontName','宋体','Location','northoutside','Orientation','horizontal');
nexttile;bar(categorical({'A','B','C'}),Comparison.ACGridCost_Yuan/1e4,'FaceColor',colors(2,:));
title('交流回代后的关口购电费用','FontName','宋体');ylabel('费用 / 万元','FontName','宋体');
nexttile;bar(categorical({'A','B','C'}),Comparison.MaxACVoltageError/1e-7,'FaceColor',colors(3,:));
title('模型与交流电压的最大偏差','FontName','宋体');ylabel('电压偏差 / (10^{-7} p.u.)','FontName','宋体');
finish(f,folder,sprintf('Fig_Week1_ObjectiveComparison_%d',id));

%% 独立校验表：只对本人目标A施加全部通过的断言，C按实际结果分析。
Metric={'SimultaneousPower_MW';'IntegerError';'SoCViolation';'TerminalSoCError';...
    'EnergyBalance_MWh';'PowerViolation_MW';'PVViolation_MW';'ActiveBalance_pu';...
    'ReactiveBalance_pu';'VoltageEquation_pu';'ConeGap';'ACVoltageViolation_pu';'ACConvergenceFailure'};
Value=[c.MaxSimultaneousPower_MW;c.IntegerError;max([0;.2-c.MinSoC;c.MaxSoC-.8]);...
    c.TerminalSoCError;c.EnergyBalanceError_MWh;c.PowerLimitViolation_MW;c.PVLimitViolation_MW;...
    c.ActiveBalanceError_pu;c.ReactiveBalanceError_pu;c.VoltageEquationError_pu;c.MaxConeGap;...
    max([0;.95-c.MinACVoltage;c.MaxACVoltage-1.05]);double(~c.ACConverged)];
Tolerance=[1e-6;1e-6;1e-6;1e-6;1e-6;1e-5;1e-5;1e-7;1e-7;1e-7;1e-5;1e-6;0];
Passed=Value<=Tolerance;Validation=table(Metric,Value,Tolerance,Passed);
assert(all(Passed),'本人目标的独立数值校验未全部通过。');disp(Validation);
% 从节点有功平衡独立计算交流关口功率，而非使用模型的P_grid代替。
ac_loss=zeros(1,T);ac_grid=zeros(1,T);opts=mpoption('verbose',0,'out.all',0,'pf.tol',1e-10);
for t=1:T
    ac=d.mpc;ac.bus(:,3)=d.PloadMW(:,t);ac.bus(:,4)=d.QloadMvar(:,t);
    ac.bus(d.pv_buses,3)=ac.bus(d.pv_buses,3)-d.PpvMW(:,t);
    ac.bus(d.ess_buses,3)=ac.bus(d.ess_buses,3)+d.PchMW(:,t)-d.PdisMW(:,t);
    r=runpf(ac,opts);assert(r.success==1);ac_loss(t)=sum(real(get_losses(r)));ac_grid(t)=sum(r.gen(:,2));
end
Hourly=table((1:T)',sum(d.PloadMW,1)',sum(d.PpvMaxMW,1)',sum(d.PpvMW,1)',...
    (d.Sbase*d.Pgrid)',ac_grid',ac_loss',min(assigned.VAC,[],1)',max(assigned.VAC,[],1)',...
    'VariableNames',{'Hour','Load_MW','PVAvailable_MW','PVUsed_MW','ModelGrid_MW',...
    'ACGrid_MW','ACLoss_MW','MinVoltage_pu','MaxVoltage_pu'});
for i=1:numel(d.ess_buses)
    Hourly.(sprintf('Charge_Node%d_MW',d.ess_buses(i)))=d.PchMW(i,:)';
    Hourly.(sprintf('Discharge_Node%d_MW',d.ess_buses(i)))=d.PdisMW(i,:)';
    Hourly.(sprintf('SoC_Node%d',d.ess_buses(i)))=d.SoC(i,:)';
end
Parameters=struct('Case',d.case_name,'Alpha',alpha,'AssignedObjective','A','Buses',d.ess_buses,...
    'BusCount',nb,'BranchCount',nl,'TimeSteps',T,'dt_h',d.dt,'BaseMVA',d.Sbase,...
    'PVPeakPerBus_MW',1.2,'StoragePowerPerBus_MW',1.5,'StorageEnergyPerBus_MWh',3,...
    'EtaCharge',d.eta_ch,'EtaDischarge',d.eta_dis,'SoCMin',.2,'SoCMax',.8,'SoCInitial',.5,...
    'VoltageMin_pu',.95,'VoltageMax_pu',1.05,'LossWeightA',.01);
Summary=struct('Student',Student,'Parameters',Parameters,'AssignedCheck',c,...
    'Comparison',table2struct(Comparison),'Validation',table2struct(Validation),...
    'Baseline',rmfield(Baseline,{'Voltage','LossMW','GridMW'}),...
    'PVAvailable_MWh',sum(d.PpvMaxMW,'all')*d.dt,...
    'TotalCharge_MWh',sum(d.PchMW,'all')*d.dt,'TotalDischarge_MWh',sum(d.PdisMW,'all')*d.dt,...
    'StorageConversionLoss_MWh',sum(d.PchMW-d.PdisMW,'all')*d.dt,...
    'MinACVoltageNode',min_bus,'MinACVoltageHour',min_hour,'WeakBaselineNode',weak_bus,...
    'ConeGapExercise',abs(.02-.1^2-.05^2),'MATLABVersion',version,'GurobiInterface',which('gurobi'),...
    'CompletedAt',char(datetime('now','TimeZone','Asia/Shanghai','Format','yyyy-MM-dd HH:mm:ss Z')));
writetable(Hourly,fullfile(folder,sprintf('Week1_Hourly_%d.csv',id)));
writetable(Comparison,fullfile(folder,sprintf('Week1_Comparison_%d.csv',id)));
writetable(Validation,fullfile(folder,sprintf('Week1_Validation_%d.csv',id)));
save(fullfile(folder,sprintf('Week1_results_%d.mat',id)),...
    'Student','Parameters','Runs','Baseline','Comparison','Validation','Hourly','Summary');
fid=fopen(fullfile(folder,sprintf('Week1_summary_%d.json',id)),'w','n','UTF-8');
assert(fid~=-1);fprintf(fid,'%s',jsonencode(Summary,'PrettyPrint',true));fclose(fid);
fprintf('无储能基准：网损 %.6f MWh，交流电压 [%.6f,%.6f] p.u.\n',...
    Baseline.Loss_MWh,Baseline.MinVoltage_pu,Baseline.MaxVoltage_pu);
end

function f=newfig(name,w,h)
f=figure('Name',name,'Color','w','Position',[100 100 w h]);
if isprop(f,'Theme') && exist('theme','file')==2,theme(f,'light');end
end

function finish(fig,folder,stem)
axes_handles=findall(fig,'Type','axes');
for k=1:numel(axes_handles)
    ax=axes_handles(k);set(ax,'FontName','Times New Roman','FontSize',12,...
        'Color','w','XColor','k','YColor','k','LineWidth',.8,'Box','on','TickDir','out',...
        'YGrid','on','GridAlpha',.12,'GridColor',[.5 .5 .5]);
    ax.Title.FontName='宋体';ax.Title.FontSize=14;ax.Title.FontWeight='normal';
    if ~contains(string(ax.XLabel.String),'\fontname'),ax.XLabel.FontName='宋体';end
    if ~contains(string(ax.YLabel.String),'\fontname'),ax.YLabel.FontName='宋体';end
    ax.XLabel.FontSize=13;ax.YLabel.FontSize=13;
end
set(findall(fig,'Type','legend'),'FontName','宋体','FontSize',11,'Box','off','TextColor','k');
cbs=findall(fig,'Type','colorbar');set(cbs,'FontName','Times New Roman','FontSize',11);
for k=1:numel(cbs),cbs(k).Label.FontName='宋体';end
drawnow;
exportgraphics(fig,fullfile(folder,[stem '.png']),'Resolution',600,'BackgroundColor','white');
exportgraphics(fig,fullfile(folder,[stem '.pdf']),'ContentType','vector','BackgroundColor','white');
savefig(fig,fullfile(folder,[stem '.fig']));
end
