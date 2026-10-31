function fig=ess_task3_figure(Day3)
% 学号指定目标下的储能调度与交流节点电压。
S=Day3.Objectives.(Day3.SelectedObjective);
D=S.Dispatch;T=size(D.PchMW,2);buses=D.ess_buses;
fig=figure('Color','w','Position',[80 80 1160 850]);
if isprop(fig,'Theme'),theme(fig,'light');end
tiledlayout(2,2,'TileSpacing','compact','Padding','compact');
nexttile;
stairs(1:T,(D.PdisMW-D.PchMW)','LineWidth',1.4);
yline(0,':');xlabel('时段 / h');ylabel('净放电功率 / MW');
title('储能充放电功率：放电为正，充电为负');
legend(compose('节点%d',buses),'Location','best');grid on;
nexttile;
plot(0:T,[repmat(D.SoC0,numel(buses),1),D.SoC]','LineWidth',1.5);
yline(D.SoCmin,'--');yline(D.SoCmax,'--');
xlabel('时段 / h');ylabel('荷电状态 SoC');title('各储能荷电状态');grid on;
nexttile;
imagesc(1:T,D.mpc.bus(:,1),S.VoltageAC);set(gca,'YDir','normal');
xlabel('时段 / h');ylabel('节点编号');title('全网交流节点电压时序分布');
cb=colorbar;cb.Label.String='电压 / p.u.';
nexttile;
plot(1:T,min(S.VoltageAC,[],1),'LineWidth',1.5);hold on;
plot(1:T,max(S.VoltageAC,[],1),'LineWidth',1.5);
yline(0.95,'--');yline(1.05,'--');ylim([0.94 1.06]);
xlabel('时段 / h');ylabel('电压 / p.u.');title('交流潮流最低与最高节点电压');
legend('最低电压','最高电压','Location','best');grid on;
sgtitle(sprintf('潘子岩 206221322 | 任务三指定目标%s',Day3.SelectedObjective));
set(findall(fig,'-property','FontName'),'FontName','PingFang SC');
set(findall(fig,'Type','axes'),'FontSize',11);
end
