function run_week1
root=fileparts(fileparts(mfilename('fullpath')));
for task=1:3
    source=fullfile(root,sprintf('maoyang_206221321_Week1_Task%d.m',task));
    evalin('base',sprintf('run(''%s'');',strrep(source,'''','''''')));
end
end
