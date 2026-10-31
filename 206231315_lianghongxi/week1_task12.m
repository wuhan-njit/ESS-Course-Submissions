function Task12=week1_task12(folder,Student,case_dir,task)
% 第一周任务一、二：独立计算0.8MW光伏基态和2MW/2MWh单站套利。
if nargin<4,task=0;end
profiles=load(fullfile(case_dir,'profiles_24h.mat'));
colors=[60 84 136;0 160 135;230 75 53]/255;
if task~=2
mpc=loadcase(fullfile(case_dir,'case_chengshi_A.m'));
alpha=1+0.002*mod(Student.ID,100);buses=[4 9 14];T=profiles.T;
opts=mpoption('verbose',0,'out.all',0,'pf.tol',1e-10);
PF=struct;
for multiplier=[1 1.1]
    v=zeros(size(mpc.bus,1),T);loss=zeros(T,1);
    for t=1:T
        c=mpc; % 每时段重新复制基准，禁止在上时段结果上累乘负荷。
        c.bus(:,3)=mpc.bus(:,3)*alpha*multiplier*profiles.load_curve_pu(t);
        c.bus(:,4)=mpc.bus(:,4)*alpha*multiplier*profiles.load_curve_pu(t);
        c.bus(buses,3)=c.bus(buses,3)-0.8*profiles.pv_curve_pu(t);
        r=runpf(c,opts);assert(r.success==1,'任务一交流潮流未收敛。');
        v(:,t)=r.bus(:,8);loss(t)=sum(real(get_losses(r)));
    end
    [minv,ix]=min(v(:));[node,hour]=ind2sub(size(v),ix);
    stat=struct('LoadMultiplier',multiplier,'Alpha',alpha*multiplier,...
        'PVPerBus_MW',.8,'MinVoltage_pu',minv,'MinVoltageNode',node,...
        'MinVoltageHour',hour,'MaxVoltage_pu',max(v(:)),...
        'DailyLoss_MWh',sum(loss),'NoonMinVoltage_pu',min(v(:,12)),...
        'EveningMinVoltage_pu',min(v(:,19)),...
        'NoonLoss_MW',loss(12),'EveningLoss_MW',loss(19),'ConvergedHours',T);
    if multiplier==1,key='Base';else,key='IncreasedLoad';end
    PF.(key)=struct('Voltage',v,'Loss_MW',loss,'Summary',stat);
end
Task1Comparison=struct2table([PF.Base.Summary PF.IncreasedLoad.Summary]);
writetable(Task1Comparison,fullfile(folder,'Week1_Task1_Comparison_206231315.csv'));
v=PF.Base.Voltage;node=PF.Base.Summary.MinVoltageNode;
f=newfig('任务一：0.8MW光伏时序潮流',1100,480);
tiledlayout(1,2,'TileSpacing','compact','Padding','compact');
nexttile;imagesc(1:T,1:size(v,1),v);axis xy;colormap(parula);
cb=colorbar;cb.Label.String='电压 / p.u.';
title('任务一：全网24小时交流电压');xlabel('时段 / h');ylabel('节点编号');
nexttile;plot(1:T,v(node,:),'-o','Color',colors(1,:),'LineWidth',2,'MarkerIndices',1:3:T);hold on;
plot(1:T,PF.IncreasedLoad.Voltage(node,:),'--s','Color',colors(3,:),'LineWidth',2,'MarkerIndices',2:3:T);
legend({'原负荷倍率1.03','负荷增加10%，倍率1.133'},'Location','northoutside','AutoUpdate','off');
title(sprintf('薄弱节点%d的全天电压',node));xlabel('时段 / h');ylabel('电压 / p.u.');xlim([1 T]);
finish(f,folder,'Fig_Week1_Task1_206231315');
f=newfig('任务一：负荷灵敏度',1100,480);
tiledlayout(1,2,'TileSpacing','compact','Padding','compact');nexttile;
plot(1:T,PF.Base.Loss_MW,'-o','LineWidth',2,'Color',colors(1,:),'MarkerIndices',1:3:T);hold on;
plot(1:T,PF.IncreasedLoad.Loss_MW,'--s','LineWidth',2,'Color',colors(3,:),'MarkerIndices',2:3:T);
legend({'原负荷','负荷增加10%'},'Location','northoutside','AutoUpdate','off');
title('逐时交流有功网损');xlabel('时段 / h');ylabel('网损 / MW');xlim([1 T]);
nexttile;plot(1:size(v,1),v(:,12),'-','Color',colors(1,:),'LineWidth',2);hold on;
plot(1:size(v,1),PF.IncreasedLoad.Voltage(:,12),'--','Color',colors(1,:),'LineWidth',2);
plot(1:size(v,1),v(:,19),'-','Color',colors(3,:),'LineWidth',2);
plot(1:size(v,1),PF.IncreasedLoad.Voltage(:,19),'--','Color',colors(3,:),'LineWidth',2);
legend({'午间原负荷','午间增加10%','晚峰原负荷','晚峰增加10%'},'Location','northoutside','NumColumns',2,'AutoUpdate','off');
title('午间与晚高峰节点电压');xlabel('节点编号');ylabel('电压 / p.u.');xlim([1 size(v,1)]);
finish(f,folder,'Fig_Week1_Task1_Sensitivity_206231315');
Task12=struct('Student',Student,'Task1',table2struct(Task1Comparison));
save(fullfile(folder,'Week1_Task1_results_206231315.mat'),'PF','Task1Comparison','Task12');
write_json(folder,'Week1_Task1_summary_206231315.json',Task12);
disp(Task1Comparison);
if task==1,return;end
end

%% 单节点套利：独立于网络约束，LP使用linprog、MILP使用intlinprog。
T=profiles.T;
MILP=arbitrage(profiles.price_MWh,2,2,true);
LP=arbitrage(profiles.price_MWh,2,2,false);
assert(abs(LP.Revenue_Yuan-MILP.Revenue_Yuan)<=1e-4,'正电价LP/MILP收益不一致。');
ArbitrageComparison=struct2table([LP.Check MILP.Check]);
writetable(ArbitrageComparison,fullfile(folder,'Week1_Task2_LP_MILP_206231315.csv'));
p_values=[.1 .25 .5 1 2 4];e_values=[1 2 3 4 6 8];
sensitivity=struct('VariedParameter',{},'Power_MW',{},'Energy_MWh',{},'Revenue_Yuan',{});
for power=p_values
    a=arbitrage(profiles.price_MWh,power,2,true);
    sensitivity(end+1)=struct('VariedParameter','Power','Power_MW',power,...
        'Energy_MWh',2,'Revenue_Yuan',a.Revenue_Yuan); %#ok<AGROW>
end
for energy=e_values
    a=arbitrage(profiles.price_MWh,2,energy,true);
    sensitivity(end+1)=struct('VariedParameter','Energy','Power_MW',2,...
        'Energy_MWh',energy,'Revenue_Yuan',a.Revenue_Yuan); %#ok<AGROW>
end
Sensitivity=struct2table(sensitivity);
writetable(Sensitivity,fullfile(folder,'Week1_Task2_Sensitivity_206231315.csv'));
Task2Hourly=table((1:T)',profiles.price_MWh(:),MILP.Pch, MILP.Pdis, MILP.SoC,...
    LP.Pch,LP.Pdis,LP.SoC,'VariableNames',{'Hour','Price_YuanPerMWh',...
    'MILP_Charge_MW','MILP_Discharge_MW','MILP_SoC','LP_Charge_MW','LP_Discharge_MW','LP_SoC'});
writetable(Task2Hourly,fullfile(folder,'Week1_Task2_Hourly_206231315.csv'));
f=newfig('任务二：电价、功率与SoC',1050,750);
tiledlayout(3,1,'TileSpacing','compact','Padding','compact');nexttile;
stairs(1:T,profiles.price_MWh(:)/1000,'Color',[.49 .37 .27],'LineWidth',2);
title('江苏分时电价');ylabel('电价 / (元/kWh)');xlim([1 T]);
nexttile;stairs(1:T,MILP.Pch,'--','Color',colors(1,:),'LineWidth',2);hold on;
stairs(1:T,MILP.Pdis,'-','Color',colors(2,:),'LineWidth',2);
legend({'充电功率','放电功率'},'Location','northoutside','Orientation','horizontal','AutoUpdate','off');
ylabel('功率 / MW');xlim([1 T]);
nexttile;plot(0:T,[.5;MILP.SoC]*100,'-o','LineWidth',2,'Color',colors(1,:),'MarkerIndices',1:3:T+1);hold on;
plot(0:T,[.5;LP.SoC]*100,'--s','LineWidth',1.5,'Color',colors(2,:),'MarkerIndices',2:3:T+1);
legend({'MILP','LP'},'Location','northoutside','Orientation','horizontal','AutoUpdate','off');
ylabel('荷电状态 / %');xlabel('时间 / h');xlim([0 T]);ylim([0 105]);
sgtitle(sprintf('2MW/2MWh：MILP日净收益 %.2f 元',MILP.Revenue_Yuan),'FontName','宋体');
finish(f,folder,'Fig_Week1_Task2_206231315');
f=newfig('任务二：功率与容量灵敏度',1100,480);
tiledlayout(1,2,'TileSpacing','compact','Padding','compact');nexttile;
plot(p_values,[sensitivity(1:numel(p_values)).Revenue_Yuan],'-o','LineWidth',2,'Color',colors(1,:));
title('能量容量固定为2MWh');xlabel('额定功率 / MW');ylabel('日收益 / 元');
nexttile;plot(e_values,[sensitivity(numel(p_values)+1:end).Revenue_Yuan],'-s','LineWidth',2,'Color',colors(2,:));
title('额定功率固定为2MW');xlabel('额定能量容量 / MWh');ylabel('日收益 / 元');
finish(f,folder,'Fig_Week1_Task2_Sensitivity_206231315');
Task12=struct('Student',Student,...
    'Task2Comparison',table2struct(ArbitrageComparison),'Task2Sensitivity',table2struct(Sensitivity),...
    'SoldEnergyFrom1MWh',.9*.95,'LP_MILP_RevenueDifference',abs(LP.Revenue_Yuan-MILP.Revenue_Yuan));
save(fullfile(folder,'Week1_Task2_results_206231315.mat'),...
    'LP','MILP','ArbitrageComparison','Sensitivity','Task2Hourly','Task12');
write_json(folder,'Week1_Task2_summary_206231315.json',Task12);
disp(ArbitrageComparison);disp(Sensitivity);
fprintf('手算：充入1MWh可售出 %.3f MWh。\n',Task12.SoldEnergyFrom1MWh);
end

function write_json(folder,name,data)
fid=fopen(fullfile(folder,name),'w','n','UTF-8');assert(fid~=-1);
fprintf(fid,'%s',jsonencode(data,'PrettyPrint',true));fclose(fid);
end

function a=arbitrage(price,power,energy,binary)
yalmip('clear');T=numel(price);eta_ch=.90;eta_dis=.95;
pch=sdpvar(T,1);pdis=sdpvar(T,1);soc=sdpvar(T,1);
c=[0<=pch<=power,0<=pdis<=power,.1<=soc<=1,soc(T)==.5];
if binary
    u=binvar(T,1);c=[c,pch<=power*u,pdis<=power*(1-u)];solver='intlinprog';
else
    solver='linprog';
end
c=[c,soc-[.5;soc(1:T-1)]==(.9*pch-pdis/.95)/energy];
original_path=path;restore=onCleanup(@()path(original_path)); %#ok<NASGU>
addpath(fullfile(matlabroot,'toolbox','optim','optim'),'-begin');
assert(startsWith(which(solver),matlabroot,'IgnoreCase',true),'必须使用MATLAB原生求解器。');
ops=sdpsettings('solver',solver,'verbose',0);
if binary,ops.intlinprog.RelativeGapTolerance=1e-8;ops.intlinprog.AbsoluteGapTolerance=1e-8;end
sol=optimize(c,-sum(price(:).*(pdis-pch)),ops);assert(sol.problem==0,'%s: %s',solver,sol.info);
a=struct('Pch',value(pch),'Pdis',value(pdis),'SoC',value(soc));
a.Revenue_Yuan=sum(price(:).*(a.Pdis-a.Pch));
res=energy*(a.SoC-[.5;a.SoC(1:T-1)])-(eta_ch*a.Pch-a.Pdis/eta_dis);
check=struct('Model',char('LP'),'Solver',solver,'Power_MW',power,'Energy_MWh',energy,...
    'Revenue_Yuan',a.Revenue_Yuan,'MaxSimultaneous_MW',max(min(a.Pch,a.Pdis)),...
    'EnergyResidual_MWh',max(abs(res)),'TerminalSoCError',abs(a.SoC(end)-.5),...
    'MinSoC',min(a.SoC),'MaxSoC',max(a.SoC),...
    'PowerViolation_MW',max([0;a.Pch-power;a.Pdis-power;-a.Pch;-a.Pdis]),'IntegerError',0);
if binary,check.Model='MILP';check.IntegerError=max(abs(value(u)-round(value(u))));end
check.Passed=check.EnergyResidual_MWh<=1e-6 && check.TerminalSoCError<=1e-6 &&...
    check.MinSoC>=.1-1e-6 && check.MaxSoC<=1+1e-6 && check.PowerViolation_MW<=1e-6 &&...
    check.MaxSimultaneous_MW<=1e-6 && check.IntegerError<=1e-6;
assert(check.Passed,'套利模型独立校验未通过。');a.Check=check;
end

function f=newfig(name,w,h)
f=figure('Name',name,'Color','w','Position',[100 100 w h]);
if isprop(f,'Theme') && exist('theme','file')==2,theme(f,'light');end
end

function finish(fig,folder,stem)
axs=findall(fig,'Type','axes');
for k=1:numel(axs)
    ax=axs(k);set(ax,'FontName','Times New Roman','FontSize',12,'Color','w',...
        'XColor','k','YColor','k','LineWidth',.8,'Box','on','TickDir','out','YGrid','on','GridAlpha',.12);
    ax.Title.FontName='宋体';ax.Title.FontSize=14;ax.Title.FontWeight='normal';
    ax.XLabel.FontName='宋体';ax.YLabel.FontName='宋体';ax.XLabel.FontSize=13;ax.YLabel.FontSize=13;
end
set(findall(fig,'Type','legend'),'FontName','宋体','FontSize',11,'Box','off','TextColor','k');
cbs=findall(fig,'Type','colorbar');set(cbs,'FontName','Times New Roman','FontSize',11);
for k=1:numel(cbs),cbs(k).Label.FontName='宋体';end
drawnow;
exportgraphics(fig,fullfile(folder,[stem '.png']),'Resolution',600,'BackgroundColor','white');
exportgraphics(fig,fullfile(folder,[stem '.pdf']),'ContentType','vector','BackgroundColor','white');
savefig(fig,fullfile(folder,[stem '.fig']));
end
