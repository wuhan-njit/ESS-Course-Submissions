function lesson=ess_live_setup
lesson.home=fileparts(fileparts(mfilename('fullpath')));
lesson.found=true;
lesson.cases=fullfile(lesson.home,'data');
lesson.results=fullfile(lesson.home,'results');
addpath(fileparts(mfilename('fullpath')),lesson.cases);
if ~isfolder(lesson.results),mkdir(lesson.results);end
end
