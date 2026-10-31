function ess_live_export(fig,folder,name)
% 按课程要求导出白底 PNG、矢量 PDF 和 FIG。
if ~isfolder(folder), mkdir(folder); end
exportgraphics(fig,fullfile(folder,[name '.png']),'Resolution',600,'BackgroundColor','white');
exportgraphics(fig,fullfile(folder,[name '.pdf']),'ContentType','vector','BackgroundColor','white');
savefig(fig,fullfile(folder,[name '.fig']));
end
