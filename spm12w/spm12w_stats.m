function results = spm12w_stats(varargin)
% spm12w_stats(stat, y, x)
%
% Input
% -----
% stat : Statistic type ('zscore' or 'l1')
%
% y    : Data matrix of Y values 
%
% x    : Data matrix of X values  
%
% Returns
% -------
% results : Results of statistical test (format depends on stat type)
%
% All purpose warehouse for statistics not built into matlab or, as in the case
% of z-score, requiring toolbox which may or may not be available (i.e, stats 
% toolbox). If the statistic doesn't require [y,x] data, then input the
% dataset under 'y'. 
%
% stat types
% ----------
% 'zscore' : z-score (i.e., y-mean(y) ./std(ya))
% 'l1'     : l1 Regression (i.e., Least Absolute Deviation)
% 'mad_med': Median Absolute Deviation (MAD)
% 'ttest1' : One-sample t-ttest against zero.
%
% Examples:
%
% Z-score a timeseries
%   >> results = spm12w_stats('stat', 'zscore', 'y', y_timeseries)
%
% Perform L1 Least Absolute Deviation
%   >> results = spm12w_stats('stat', 'l1', 'y', y, 'x', x)
%
% Test code for L1 Regression
% ---------------------------
% n = 30;  rand('twister',2323);  randn('state',1865);
% BTrue = [1 -2];
% X = sort(rand(n,1));
% Y = BTrue(1) + X * BTrue(2) + 0.05 * randn(n,1);
% Y(1) = -0.5;
% Y(end) = 0.65;
% 
% B1 = spm12w_stats('stat', 'l1', 'y', Y, 'x', X);
% BS = [ones(n,1) X] \ Y;
% 
% %timeit (l1 is faster)
% myfun = @()spm12w_stats('stat', 'l1', 'y', Y, 'x', X);
% timeit(myfun)
% 
% figure
% plot(X,Y,'bs',X,B1(1) + X * B1(2:end),'r-',X,BS(1) + X * BS(2:end),'k-')
% axis square
% grid on
% legend('Training Data','L-1 Regression','Least Squares Regression')
% 
% # spm12w was developed by the Wagner, Heatherton & Kelley Labs
% # Author: Dylan Wagner | Created: March, 2013 | Updated: December, 2014
% =======1=========2=========3=========4=========5=========6=========7=========8

% Parse inputs
args_defaults = struct('stat','', 'y',[], 'x',[]);
args = spm12w_args('nargs',4, 'defaults', args_defaults, 'arguments', varargin);

% switch on stat type.
switch args.stat 
    case 'zscore'
        results = (args.y-mean(args.y)) ./ std(args.y);
    case 'l1'
        % Algorithm from "L1LinearRegression.m" by Will Dwinnell
        % Determine size of predictor data
        % If constant/intercept was included, remove it...
        if any(args.x(:,1) == ones(length(args.x),1))
            args.x = args.x(:,2:end);
        end
        % Determine size of predictor data
        [n, m] = size(args.x);
        % Initialize with least-squares fit
        B       = [ones(n,1) args.x] \ args.y;  % Least squares regression
        BOld    = B;
        BOld(1) = BOld(1) + 1e-5;  % Force divergence
        % Repeat until convergence
        while (max(abs(B - BOld)) > 1e-6)
            % Move old coefficients
            BOld = B;
            % Calculate new observation weights (based on residuals from old coefficients)
            W = sqrt(1 ./ max(abs((BOld(1) + (args.x * BOld(2:end))) - args.y),1e-6));  % Floor to avoid division by zero
            % Calculate new coefficients
            B = (repmat(W,[1 m+1]) .* [ones(n,1) args.x]) \ (W .* args.y);
        end
        results = B;
    case 'mad_med'
        results = median(abs(args.y-median(args.y)));
    case 'ttest1'    
        [~,p,ci,stats]=ttest(args.y);
        results = struct('t',stats.tstat,'p',p,'ci',ci,'df',stats.df); 
    case 'ttest2'    
        [~,p,ci,stats]=ttest2(args.y, args.x);
        results = struct('t',stats.tstat,'p',p,'ci',ci,'df',stats.df);    
    case 'correl'
        [rcorr,p] = corrcoef(args.y, args.x);     
        results = struct('r',rcorr(1,2),'p',p(1,2));
end

% Create significance stars for statistics (ttest1, ttest2, correl)
if isstruct(results)
    switch logical(true)
        case results.p < 0.001
            results.p_star = '***';
        case p < 0.01
            results.p_star = '**';                                                       
        case results.p < 0.05
            results.p_star = '*';
        otherwise
            results.p_star = '';
    end
end