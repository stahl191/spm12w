function spm12w_glm_compute(varargin)
% spm12w_glm_design('sub_id','glm_file')
%
% Inputs
% ------
% sid:      Subject ID of subject for glm computation (e.g., 's01')
%
% glm_file: File specifying the parameters for glm design and contrasts
%           (e.g., 'glm_tutorial.m'). If the full path is left unspecified,
%           spm12w_glm will look in the scripts directory. <optional>
%
% spm12w_glm_compute will gather onset files and specify a design matrix 
% which will be used to compute parameter estimates for a variety of designs.
% spm12w_glm_compute supports a variety of designs: event-related, block,
% regressor-only (e.g., PPI), state-item, and combinations of event, block
% and regressor designs. In addition, spm12w_glm_compute will generate
% outlier, movement and nuissance regressors to be included in the design
% matrix. 
%
% spm12w_glm_compute may also be used to specify a design without data if 
% the design_only parameter is set to 1 in the glm parameter file. In 
% this case the user must supply the tr, nses and nvols in the glm
% parameter file. Otherwise these parameters will be pulled from saved
% parameters in the prep directory specified by the user. 
%
% The first argument is a sid. The second argument is the name of a glm 
% parameter files (e.g., glm_tutorial.m) and is optional. If the parameter 
% file is unspecified, matlab will prompt the user to select the file.
%
% A pdf file (glmname.pdf) will be written to the analysis/username/glm_name 
% directory and contains a figure of the design matrix. 
%
% NB: Design matrices generated by spm12w_glm_compute build were tested against
% the same parameters in the SPM 12 gui and produced identical designs.
%
% Examples:
%
%       >>spm12w_glm_compute('sid','s01')
%       >>spm12w_glm_compute('sid','s01','glm_file', ...
%                           './scripts/username/glm_tutorial.m')
%
% # spm12w was developed by the Wagner, Heatherton & Kelley Labs
% # Author: Dylan Wagner | Created: March, 2006 | Updated: May, 2015
% =======1=========2=========3=========4=========5=========6=========7=========8

% Parse inputs
args_defaults = struct('sid','', 'glm_file','');
args = spm12w_args('nargs',2, 'defaults', args_defaults, 'arguments', varargin);

% Load glm parameters
glm = spm12w_getp('type','glm', 'sid',args.sid, 'para_file',args.glm_file);

% Setup directories for GLM analysis. 
spm12w_dirsetup('dirtype','glm','params',glm);

% Setup logfile
spm12w_logger('msg','setup_glm', 'level',glm.loglevel, 'params',glm)

% Goto glm directory
cd(glm.glmdir)

% If glm file has missing parameters, get them from the prep file. 
if isfield(glm, 'nses') && isfield(glm, 'nvols') && isfield(glm, 'tr')
    % Do nothing, estimation is go. 
elseif exist(fullfile(glm.datadir,[glm.prep_name,'.mat']),'file')
    load(fullfile(glm.datadir,[glm.prep_name,'.mat']))
    spm12w_logger('msg',sprintf(['Loading additional parameters from: ', ...
              '%s.mat'],glm.prep_name),'level',glm.loglevel)
    for pfield = {'nses','nvols','tr','ra','fmri','cleanupzip'};
        glm.(pfield{1}) = p.(pfield{1});
    end
    clear p % remove p structure for safety
else
    spm12w_logger('msg', ['[EXCEPTION] Required parameters (nses, ', ...
                  'nvols, tr) are unspecified and a prep parameter file ', ...
                  'was not found.'], 'level',glm.loglevel)
    diary off
    error('Missing required parameters for model estimation (nses, nvols, tr)')     
end

% Show user the parameters we harvested.
for ses = 1:glm.nses
    spm12w_logger('msg', sprintf('Run:%d, nvols=%d, TR=%.1f', ses, ...
                  glm.nvols(ses), glm.tr(ses)), 'level', glm.loglevel);
end

% Adjust nses & nvols to match modeled runs.
if strcmp(glm.include_run,'all')
    glm.include_run = 1:glm.nses;
    idx_bool = ones(sum(glm.nvols),1); % keep all volumes
elseif max(glm.include_run > glm.nses)
    spm12w_logger('msg', sprintf(['[EXCEPTION] Included run (%d) exceeds ', ...
              'available runs (%d)'], max(glm.include_run),glm.nses), ...
              'level', glm.loglevel)
    error('Included run exceeds available runs...')
else
    % Generate an index of volumes to be modeled (for use in identifying onsets)
    idx_bool = zeros(sum(glm.nvols),1);
    vol = 1;
    for i_ses = 1:glm.nses
        for i_vols = 1:glm.nvols(i_ses)
            if any(i_ses==glm.include_run)
                idx_bool(vol) = 1;
            end
                vol = vol + 1;
        end
    end
    % Adjust nses & nvols to match modeled runs.
    glm.nses = length(glm.include_run);
    glm.nvols = glm.nvols(glm.include_run);
    % Assign TR to runs to be modeled
    glm.tr = glm.tr(glm.include_run);
end

% Check that the runs to be modeled all have same TR
if length(unique(glm.tr)) > 1
    spm12w_logger('msg', sprintf(['[EXCEPTION] Runs to be modeled have ', ...
              'different TRs (%s)'], sprintf('Run %.1f ',glm.tr)), ...
              'level', glm.loglevel)
    error('Modeled runs do not all have the same TR...')
else
    glm.tr = unique(glm.tr);
end

% Tell the user what we're up to...
msg = sprintf('GLM will be calculated on runs: %s', ...
               sprintf('%d(nvols=%d) ',[glm.include_run;glm.nvols]));
spm12w_logger('msg', msg, 'level', glm.loglevel)

% Build simple model from onsets and nuissance regressors.
for mfield = {'events','blocks','regressors'};
    if ~isempty(glm.(mfield{1}))
        glm = spm12w_glm_build('type',mfield{1},'params',glm);
    end
end
for mfield = {'outliers','nuissance','move'};
    if glm.(mfield{1}) == 1
        glm = spm12w_glm_build('type',mfield{1},'params',glm);
    end
end   

% Adjust onsets, durations, parametrics and regressors for the included runs.
% If user is modeling fewer than the total number of sessions then 
% onsets (which always describe all runs) need to be adjusted by removing 
% the excluded run(s) and by altering the value of the onsets following the
% excluded run(s). 
if any(idx_bool == 0) % only adjust if necessary.
    spm12w_logger('msg',sprintf(['Adjusting onsets, durations,  ',...
                  'parametrics and/or regressors for the included runs: %s'], ...
                  mat2str(glm.include_run)), 'level',glm.loglevel)  
    for fname = fieldnames(glm.X_onsets)'
        if ismember(fname, glm.regressors)
            % If the onsets are regressors then different trick
            glm.X_onsets.(fname{1}).ons(idx_bool==0) = [];
        else
            % Onset type is block or events.
            % Create vectors describing every volume in the design
            ons_idx = zeros(length(idx_bool),1);
            % Mark 1 where onsets should be in the design     
            ons_idx(glm.X_onsets.(fname{1}).ons+1) = 1; % +1 for 0 to 1 indexing
            % Make new vectors for onsets and durations in same place
            ons = ons_idx;
            dur = ons_idx;
            % Put durations at same place as onsets
            dur(dur==1) = glm.X_onsets.(fname{1}).dur;
            % Remove all volumes for excluded runs based on idx_bool made above
            dur(idx_bool==0) = [];
            ons(idx_bool==0) = [];
            % Pop out all zeros from the new duration vector.
            dur(ons==0) = [];
            % Assign onsets and durations back to structure
            glm.X_onsets.(fname{1}).ons = find(ons==1)-1; % -1 for 1 to 0 indexing
            glm.X_onsets.(fname{1}).dur = dur;
            % Do same for parametrics
            if isfield(glm.X_onsets.(fname{1}),'P')
                for p_i = 1:length(glm.X_onsets.(fname{1}).P)
                    para = ons_idx;
                    para(para==1) = glm.X_onsets.(fname{1}).P(p_i).P;
                    para(idx_bool==0) = [];
                    para(ons==0) = [];
                    glm.X_onsets.(fname{1}).P(p_i).P = para;
                end            
            end
        end
    end
end


% Fill in SPM structure prior to design specification
glm.SPM = spm12w_getspmstruct('type','glm','params',glm);

% Do seperate steps if design_only  == 1 or 0
if glm.design_only == 0
    spm12w_logger('msg','Generating SPM design matrix...','level',glm.loglevel)
    % Print files being used and also (stealth) check if they are zipped.
    for file_i = 1:size(glm.SPM.xY.P,1)
        epifile = deblank(glm.SPM.xY.P(file_i,:));
        spm12w_logger('msg',sprintf('Loading file: %s', epifile), ...
                      'level',glm.loglevel)  
        if glm.cleanupzip == 1 
            gunzip([epifile,'.gz'])
        end        
    end
    
    % Generate an empty figure to catch the SPM design
    F = spm_figure('CreateWin','Graphics', 'spm12w glm', 'off'); 

    % Generate design using SPM structure.
    glm.SPM = spm_fmri_spm_ui(glm.SPM);

    % Hide F right away (unlike preprocessing, spm_fmri_spm_ui will
    % set a hidden figure to visible). 
    set(F,'visible','off');
    % Print looks better using opengl for design matrices. Keep an eye on
    % this in case it fails on other platforms. opengl throws running in parfor
    % but completed anyway.
    print(F, 'glm.ps', '-dpsc2','-opengl','-append','-noui') 
    
    % Demean design if user requested
    if glm.demean == 1
        reg_interest = size(glm.SPM.Sess.U,2);
        for i = 1:size(glm.SPM.Sess.U,2)
            for ii = 1:size(glm.SPM.Sess.U(i).P,2)
                if strfind(glm.SPM.Sess.U(i).P(ii).name,'other')
                    reg_interest = reg_interest + 1;
                end
            end
        end
        for i = 1:reg_interest
            glm.SPM.xX.X(:,i)=spm_detrend(glm.SPM.xX.X(:,i),0);
        end
    end
    % Specify mask
    [~,maskname] = fileparts(glm.mask);
    glm.SPM.xM.VM = spm_vol(glm.mask);
    glm.SPM.xM.T  = [];
    glm.SPM.xM.TH = ones(size(glm.SPM.xM.TH))*(-Inf);
    glm.SPM.xM.I  = 0;
    glm.SPM.xM.xs = struct('Masking', sprintf('explicit masking only - using %s',maskname));
    spm12w_logger('msg',sprintf(['The SPM.mat file has been modified to ',...
                  'use mask: %s'], maskname), 'level',glm.loglevel)  
    % Estimate model
    spm12w_logger('msg',sprintf('Estimating parameters for model: %s', ...
                  glm.glm_name), 'level',glm.loglevel) 
    glm.SPM = spm_spm(glm.SPM);
    
    % Add effects of interest contrast (nice to have and necessary for
    % adjusting timecourses during VOI extraction for PPI). 
    Fcname = 'effects of interest';
    iX0    = 1:glm.SPM.xX.iB;   %Set iX0 to span all regressors
    %Count number of nuissance 'r-'egs and add +1 for constant
    len = sum(cell2mat(strfind(glm.SPM.Sess.C.name,'r-')))+1;   
    iX0(1:end-len) = []; %Remove all but the nuissance regressors
    glm.SPM.xCon = spm_FcUtil('Set',Fcname,'F','iX0',iX0,glm.SPM.xX.xKXs);
    % Save to SPM structure
    SPM = glm.SPM;
    save('SPM.mat','SPM')       
    % Remove the unzipped files if they were previously zipped
    if glm.cleanupzip == 1 
        for file_i = 1:size(glm.SPM.xY.P,1)
            epifile = deblank(glm.SPM.xY.P(file_i,:));
            delete(epifile)
        end    
    end    
    % Convert multipage ps file to pdf
    spm12w_ps2pdf('ps_file',fullfile(glm.glmdir,'glm.ps'),...
                  'pdf_file',fullfile(glm.glmdir,[glm.glm_name,'.pdf']))
    % Set final words (include figure)
    msglist{1} = glm.niceline;
    msglist{2} = sprintf('GLM specification complete on subject: %s',glm.sid);
    msglist{3} = sprintf('Log file   : %s', fullfile(glm.glmdir, glm.glmlog));
    msglist{4} = sprintf('Figures    : %s', fullfile(glm.glmdir,[glm.glm_name,'.pdf']));
    msglist{5} = sprintf('Parameters : %s', fullfile(glm.glmdir,[glm.glm_name,'.mat']));
else   
    spm12w_logger('msg','Generating SPM design matrix (design only)...','level',glm.loglevel)
    
    % Generate design using SPM structure.
    glm.SPM = spm_fmri_spm_ui(glm.SPM);
    
    % Set final words (no figure, design only)
    msglist{1} = glm.niceline;
    msglist{2} = sprintf('GLM specification complete on subject: %s',glm.sid);
    msglist{3} = sprintf('Log file   : %s', fullfile(glm.glmdir, glm.glmlog));
    msglist{4} = sprintf('Parameters : %s', fullfile(glm.glmdir,[glm.glm_name,'.mat']));
end

% Print final words
for msg = msglist
    spm12w_logger('msg',msg{1},'level',glm.loglevel)
end

% Close hidden figure (try because in some cases it might already be closed)
try
    F = spm_figure('FindWin','Graphics');
    close(F)
end

% Save parameter structure to mat file
save([glm.glm_name,'.mat'],'glm');

% Close log and return to studydir.
diary off; 
cd(glm.study_dir)