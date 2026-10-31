function ess_week1_setup(root)
addpath(fullfile(root,'data'));
addpath(fullfile(root,'helpers'));
if exist('runpf','file')~=2 || exist('sdpvar','file')~=2
    sibling=fullfile(fileparts(root),'dependencies');
    if isfolder(sibling),addpath(genpath(sibling));end
end
assert(exist('runpf','file') == 2,'MATPOWER未在MATLAB路径中。');
assert(exist('sdpvar','file') == 2,'YALMIP未在MATLAB路径中。');
end
