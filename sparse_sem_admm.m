function [sol, history] = sparse_sem_admm(S0,gamma,indA,alpha0,varargin)
%% ADMM for sparse SEM
% 
% SPARSE_SEM_ADMM solves the problem
% 
% minimize -logdet(X1) + Tr(SX1) + 2*gamma sum_{(i,j) not in indA} |(X2)ij|
% subject to  X >= 0, 0 <= X4 <= alpha*I, P(X2) = I
% 
% DEFAULT USAGE:
% 
% [SOL, H] = sparse_sem_admm(S0,gamma,indA,alpha0,x0)
%
% USAGE WITH OPTIONS:
%
% [SOL, H] = sparse_sem_admm(S0,gamma,indA,alpha0,'initial',X0,'criterion','res','maxiter',1000,'tolfun',1e-5,'tolx',1e-5,'freqprint',5)
% 
% Required input arguments: 
%   1) S0       : sample covariance matrix
%   2) gamma    : l1 regularization parameter
%   3) indA     : linear indices that A_ij is zero (index set I_A)
%   4) alpha0 	: a problem parameter. normally we suggest to set alpha = min(eig(S0)).
% 
% 
% Optional arguments:
% 
%   5) 'initial'   : intitial solution (X0) must be a symmetric matrix with size 2n*2n
%   6) 'maxiter'   : a maximum number of iterations  (positive integer) 
%   7) 'criterion' : choices of stopping criterion 
%                   'res' using residual norm error
%                   'rel' using relative change in objective and solution
%   8) 'eabs' : absolute tolerance for residual norm  (if 'res' is chosen)
%   9) 'erel' : relative tolerance for residual norm (if 'res' is chosen)
%   10) 'tolfun'  : tolerance of the relative change of cost function(f) (if 'rel' is chosen)
%   11) 'tolx'    : tolerance of the relative change of solution (X) (if 'rel' is chosen)
%   12) 'freqprint': frequency of printing algorithm iterations on screen
% 
% Returned output arguments: 
% 
%   1) SOL: a structure variable with the fields
%      SOL.X : a symmtric X = [X1 X2 ; X2 X4] each Xk is n x n
%      SOL.A : our estimated path matrix
%   2) HISTORY: a struture variable containing historical algorithm values
%      objective values, relative change in X and objective function, residual norms
% 
% We implement ADMM based on the global consensus problem, page 50 of
% Stephen Boyd book on Distributed Optimization
% 
% minimize f1(X1) + f2(X2) + f3(X3) 
% C = {(X1,X2,X3) | X1= X2 = X3  } 
% where 
% f1(Y) = -logdet(Y1)+ Tr(SY1) + I{ 0 <= Y4 <= alpha*I } 
% f2(Y) = 2*gamma sum_{(i,j) not in indA} |(Y2)ij| + I{ P(Y2) = I} 
% f3(Y) = I{ Y >= 0} 
% 
% I{ X in C} denotes an indicator function)
% 
% We also solve the scaled problem using (S,alpha) = (beta*S0,1) 
% where S0 is the original sample covariance and beta = 1/alpha0
% the original solution is obtained by scaling back (check Proposition 2 in the
% paper)
% 
%
% The program is based on ADMM algorithm described in
% 
% A. Pruttiakaravanich and J. Songsiri, "Convex Formulation for Regularized Estimation
% of Structural Equation Models"% 
% 
% Additional note: it requires 'det_rootn' function by CVX to compute log_det of X > 0.
% 
% Author: Anupon Pruttiakaravanich and Jitkomut Songsiri
%  Date: May 2, 2019

%% Sparse SEM
% minimize -loget(X1) + Tr(SX1) + 2*gamma \sum_{(i,j) not in I_A} | (X2)_ij | 
% subject to X >= 0, 0 <= X4 <= alpha*I , P(X2) = I
    
beta = 1/alpha0; % scaling factor
alpha = 1; % used in scaled problem
S = beta*S0; % use this S to solve the scaled problem
m = 3;  
rho = 1*beta; % heuristic choice
n = size(S0,1);
allind = (1:n^2)'; 
indnotA = setdiff(allind,indA,'rows');

%setting optional parameters (X0, criterion, maxiter, tolfun, tolx, eabs, rel)
defaultMaxIter = 50000;     %maximum iteration
defaultTolFun = 1e-7;       %relative change of f
defaultTolX = 1e-7;         %relative change of X (solution)
defaultEabs = 1e-7;         %absolute tol for residual
defaultErel = 1e-7;         %relative tol for residual
defaultFreqPrint = 10;      %printing frequency
defaultCriterion = 'rel';   %default criterion : relative error

X1 = S\eye(n); X4 = alpha*eye(n); X2 = zeros(n); X0 = [X1 X2';X2 X4];
defaultX0 = X0;

p = inputParser;

validmatrixinputS = @(x) ismatrix(x) && issymmetric(x) && (sum(size(x) == [n,n]) == 2);
validmatrixinputX = @(x) ismatrix(x) && issymmetric(x) && (sum(size(x) == [2*n,2*n]) == 2);
validScalarPosNumForMaxIter = @(x) isnumeric(x) && isscalar(x) && (x >= 10);
validScalarPosNumForCriterion = @(x) isnumeric(x) && isscalar(x) && (x > 0) && (x < 1);
validScalarPosNum = @(x) isnumeric(x) && isscalar(x) && (x > 0);
validScalarPosNumForPrint = @(x) isnumeric(x) && isscalar(x) && (x > 1);
validCriterion = {'rel','res'};
checkCriterion = @(x) any(validatestring(x,validCriterion));

addRequired(p,'S0',validmatrixinputS);
addRequired(p,'gamma',validScalarPosNum);
addRequired(p,'indA');
addRequired(p,'alpha0',validScalarPosNum);
addOptional(p,'criterion',defaultCriterion,checkCriterion);
addParameter(p,'initial',defaultX0,validmatrixinputX);
addParameter(p,'maxiter',defaultMaxIter,validScalarPosNumForMaxIter);
addParameter(p,'tolfun',defaultTolFun,validScalarPosNumForCriterion);
addParameter(p,'tolx',defaultTolX,validScalarPosNumForCriterion);
addParameter(p,'eabs',defaultEabs,validScalarPosNumForCriterion);    
addParameter(p,'erel',defaultErel,validScalarPosNumForCriterion);    
addParameter(p,'freqprint',defaultFreqPrint,validScalarPosNumForPrint);

parse(p,S0,gamma,indA,alpha0,varargin{:});  

% numerical parameters
criterion = p.Results.criterion;      	% set stopping criterion
MAXITER = p.Results.maxiter;            % set number of maximum iterations
X0 = p.Results.initial;             	% set initial guess X0
FREQ_PRINT = p.Results.freqprint; 
if(strcmp(criterion,'res'))
    E_abs = p.Results.eabs;             % absolute tolerance
    E_rel = p.Results.erel;             % relative tolerance                         
else
    TOL_RELF = p.Results.tolfun;        % relative change of cost objective
    TOL_RELX = p.Results.tolx;          % relative change of solution    
end      
PRINT_RESULT = 1;

X = repmat(X0,1,1,m); Z = X0; Y = zeros(2*n,2*n,m);
f = objval(X,S0,n,gamma,indnotA);

if(strcmp(criterion,'rel'))
   	%print information to user
    fprintf(['----------ALGORITHM PARAMETERS----------\n',...
            'stopping criterion : relative error\n',...
            'relative change of objective function (f): %0.4d\n',...
            'relative change of solution (X): %0.4d\n',...
            'maximum iteration : %d\n',...
            'printing frequency : %d\n',...
            '----------STARTING ALGORITHM----------\n'],TOL_RELF,TOL_RELX,MAXITER,FREQ_PRINT);
        
    %use relative error as stopping criterion
    if (PRINT_RESULT == 1)
        fprintf('%3s\t%10s\t%10s\t%10s\t%10s\t%10s\n', 'iter', ...
        'r norm', 's norm', 'rel change in f', 'rel change in x', 'objective');
    end
    
    for ii=1:MAXITER
        fold = f;    
        Zold = Z;

        X(:,:,1) = proxlogdet(Z-(1/rho)*Y(:,:,1),S,rho,alpha);
        X(:,:,2) = proxl1(Z-(1/rho)*Y(:,:,2),n,gamma/rho,indA,indnotA);
        X(:,:,3) = proxpdf(Z-(1/rho)*Y(:,:,3));


        Z = mean(X,3); % consensus averaging

        for k=1:m
            Y(:,:,k) = Y(:,:,k) + rho*(X(:,:,k) - Z);
        end

        % cost objective value of scaled problem
        history.objval1(ii) = objval(Z,S,n,gamma,indnotA);

        W = Z; % W is the solution of original problem
        W(1:n,1:n) = Z(1:n,1:n)*beta; W(n+1:end,n+1:end) = Z(n+1:end,n+1:end)/beta;

        % cost objective value of original problem
        history.objval(ii) = objval(W,S0,n,gamma,indnotA);

        f = history.objval(ii);
        history.relf(ii) = abs( (fold - f)/fold ) ; 
        history.relx(ii) = norm(Z-Zold)/norm(Zold);

        history.r_norm(ii) = norm( reshape(X-Z,m*(2*n)^2,1));
        history.s_norm(ii) = sqrt(m)*rho*norm(Z-Zold);

        if (PRINT_RESULT && mod(ii,FREQ_PRINT) == 0)
            fprintf('%3d\t%10.6f\t%10.6f\t%10.6f\t%10.6f\t%10.2f\n', ii, ...
            history.r_norm(ii), history.s_norm(ii), history.relf(ii), history.relx(ii),history.objval(ii));
        end

        if ( history.relf(ii)  <= TOL_RELF) && ( history.relx(ii) <= TOL_RELX )
            break;
        end
    end

    if ii == MAXITER
        history.converge = 0; display('The algorithm hits the max number of iterations');
    else
        history.converge = 1; display('relative change of X and f are less than the desired tolerance');
    end
else
    %print information to user
    fprintf(['----------ALGORITHM PARAMETERS----------\n',...
            'stopping criterion : residual error\n',...
            'absolute residual tolerance: %0.4d\n',...
            'relative residual tolerance: %0.4d\n',...
            'maximum iteration : %d\n',...
            'printing frequency : %d\n',...
            '----------STARTING ALGORITHM----------\n'],E_abs,E_rel,MAXITER,FREQ_PRINT)
    
    if (PRINT_RESULT == 1)
        fprintf('%3s\t%10s\t%10s\t%10s\t%10s\t%10s\n', 'iter', ...
        'r norm', 'eps pri', 's norm', 'eps dual', 'objective');
    end

    for ii=1:MAXITER
        fold = f;    
        Zold = Z;

        X(:,:,1) = proxlogdet(Z-(1/rho)*Y(:,:,1),S,rho,alpha);
        X(:,:,2) = proxl1(Z-(1/rho)*Y(:,:,2),n,gamma/rho,indA,indnotA);
        X(:,:,3) = proxpdf(Z-(1/rho)*Y(:,:,3));


        Z = mean(X,3); % consensus averaging

        for k=1:m
            Y(:,:,k) = Y(:,:,k) + rho*(X(:,:,k) - Z);
        end

        % cost objective value of scaled problem
        history.objval1(ii) = objval(Z,S,n,gamma,indnotA);

        W = Z; % W is the solution of original problem
        W(1:n,1:n) = Z(1:n,1:n)*beta; W(n+1:end,n+1:end) = Z(n+1:end,n+1:end)/beta;

        % cost objective value of original problem
        history.objval(ii) = objval(W,S0,n,gamma,indnotA);

        f = history.objval(ii);
        history.relf(ii) = abs( (fold - f)/fold ) ; 
        history.relx(ii) = norm(Z-Zold)/norm(Zold);

        history.eps_pri(ii) = sqrt(m*(2*n)^2)*E_abs + ...
            E_rel*max([norm(vec(X)) norm(Z(:))]) ; 
        history.eps_dual(ii) = sqrt(m*(2*n)^2)*E_abs + ...
            E_rel*norm(vec(Y));

        history.r_norm(ii) = norm( reshape(X-Z,m*(2*n)^2,1));
        history.s_norm(ii) = sqrt(m)*rho*norm(Z-Zold);

        if (PRINT_RESULT && mod(ii,FREQ_PRINT) == 0)
             fprintf('%3d\t%10.6f\t%10.6f\t%10.6f\t%10.6f\t%10.2f\n', ii, ...
            history.r_norm(ii), history.eps_pri(ii) , history.s_norm(ii), history.eps_dual(ii), history.objval(ii));
        end

        % break program
        if ((history.r_norm(ii) < history.eps_pri(ii)) && ...
           (history.s_norm(ii) < history.eps_dual(ii)) && (history.objval(ii) ~= -Inf))
             break;
        end
    end

    if ii == MAXITER
        history.converge = 0; display('The algorithm hits the max number of iterations');
    else
        history.converge = 1; display('Residual norms are less than the desired tolerance');
    end

end

sol.X = Z; 
% use the solution X2 (from soft thresholding to get exact zeros)
sol.X(n+1:end,1:n) = X(n+1:end,1:n,2); sol.X(1:n,n+1:end) = X(1:n,n+1:end,2);
sol.X(1:n,1:n) = Z(1:n,1:n)*beta;
sol.X(n+1:end,n+1:end) = Z(n+1:end,n+1:end)/beta;

sol.A = eye(n)-sol.X(n+1:end,1:n); % A = I-X2;

%% Cost objective
function[f] = objval(X,S,n,gamma,indnotA)

X2 = X(n+1:end,1:n);
% log_det function (by CVX) cannot be used within parfor
% f = -log_det(X(1:n,1:n))+trace(S*X(1:n,1:n))+2*gamma*sum(abs(X2(indnotA)));

% det function (built-in matlab) cannot be directly used as log(det(X))
f = -n*log(det_rootn(X(1:n,1:n)))+trace(S*X(1:n,1:n))+2*gamma*sum(abs(X2(indnotA))); 
end

%% Proximal operator of loget 
% f(X) = -logdet(X1) + Tr(S*X1) + I{ 0 <= X4 <= alpha*I } 
% minimize_X -logdet(X1) + Tr(SX1) + (rho/2) || Y - X ||^2 
% subject to X1 >= 0,  0 <= X4 <= alpha*I

function[Z] = proxlogdet(Y,S,rho,alpha)

n = size(S,1); 
Z = Y; % pre-assign 

[U,D] = eig(rho*Y(1:n,1:n)-S);
d = diag(D);
Dz1 = diag(0.5*(d+sqrt(d.^2+4*rho) )/rho);
Z(1:n,1:n) = U*Dz1*U'; % modify on Z1

[U4,D4] = eig(Y(n+1:end,n+1:end));
Dz4 = diag(max(0,min(alpha,diag(D4))));
Z(n+1:end,n+1:end) = U4*Dz4*U4'; % modify on Z4

end

%% Proximal operator of l1
% minimize_X  2a sum_{(i,j) not IA} | (X_2)ij | + (1/2) || Y - X ||^2
% subject to  P(X2) = I

function[Z] = proxl1(Y,n,a,indA,indnotA)

I = eye(n);
Z = Y;
Y2 = Y(n+1:end,1:n); Z2 = zeros(n);
Z2(indnotA) = max(abs(Y2(indnotA))-a,0).*sign(Y2(indnotA)); % factor 2g/2
Z2(indA) = I(indA); % P(Z2) = I
Z(n+1:end,1:n) = Z2; Z(1:n,n+1:end) = Z2';
end

%% Proximal operator of cone constraint
% minimize_{ X >= 0 } (1/2) || Y - X ||^2

function[Z] = proxpdf(Y)

[U,D] = eig(Y);
Dz = diag([max(0,diag(D))]);
Z = U*Dz*U';
end

end