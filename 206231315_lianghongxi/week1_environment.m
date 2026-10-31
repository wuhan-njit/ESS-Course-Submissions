function case_dir=week1_environment(work_dir)
% 为第一周作业查找本机依赖；仅修改当前MATLAB会话的搜索路径。
parent=fileparts(fileparts(work_dir));
choices={fullfile(parent,'ESS-Course-Materials-main','cases'),fullfile(parent,'ESS-Course-Materials','cases')};
case_dir='';
for k=1:numel(choices)
    if isfile(fullfile(choices{k},'profiles_24h.mat')),case_dir=choices{k};break;end
end
if isempty(case_dir)
    case_file=which('case_chengshi_A');
    if ~isempty(case_file),case_dir=fileparts(case_file);end
end
assert(~isempty(case_dir),'请将课程资源库放在本仓库旁，或先将cases目录加入MATLAB路径。');
addpath(case_dir);
if exist('runpf','file')~=2
    candidates=dir(fullfile(matlabroot,'toolbox','matpower*'));
    for k=1:numel(candidates)
        root=fullfile(candidates(k).folder,candidates(k).name);
        if isfile(fullfile(root,'install_matpower.m'))
            addpath(root);install_matpower(1,0,0);break;
        end
    end
end
if exist('yalmip','file')~=2
    choices={'D:/YALMIP-master',fullfile(matlabroot,'toolbox','YALMIP-master')};
    for k=1:numel(choices)
        if isfolder(choices{k}),addpath(genpath(choices{k}));break;end
    end
end
gurobi_home=getenv('GUROBI_HOME');
if isfolder(fullfile(gurobi_home,'matlab')),addpath(fullfile(gurobi_home,'matlab'));end
if exist('gurobi','file')==0
    candidates=[dir('C:/gurobi*/win64/matlab');dir('D:/gurobi*/win64/matlab')];
    if ~isempty(candidates),addpath(fullfile(candidates(end).folder,candidates(end).name));end
end
assert(exist('runpf','file')==2,'请配置MATPOWER。');
assert(exist('yalmip','file')==2,'请配置YALMIP。');
assert(exist('gurobi','file')~=0,'请配置Gurobi MATLAB接口和有效许可证。');
end
