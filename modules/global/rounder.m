function [upper,x_min] = rounder(prelaxed,upper,x,p,relaxedoutput,lower)
% function [upper,x_min] = rounder(p,relaxedsolution,prelaxed)

% Extremely simple heuristic for finding integer solutions.

% This was the relaxed solution
x = relaxedoutput.Primal;

% Assume we fail
upper = inf;
x_min = x;

% These should be integer
intvars = [p.integer_variables(:);p.binary_variables(:)];
convars = p.noninteger_variables;

% Tidy up numerical noise within tolerance
close = find(abs(x(intvars)-round(x(intvars))<=p.options.bnb.inttol));
x(intvars(close)) = round(x(intvars(close)));

if ismember('shifted round',p.options.bnb.rounding)
    % Pre-extract...    
    if length(convars)==1 && length(p.K.s)==1 && any(p.K.s)
        H = p.F_struc(1+p.K.l+p.K.f:end,:);
        H0 = reshape(H(:,1),p.K.s(1),p.K.s(1));if nnz(H0)/numel(H0)>0.5;H0 = full(H0);end
        Hx = reshape(H(:,1+convars),p.K.s(1),p.K.s(1));if nnz(Hx)/numel(Hx)>0.5;Hx = full(Hx);end
        Hz = H(:,1 + intvars);if nnz(Hz)/numel(Hz)>0.5;Hz = full(Hz);end
    end
    % Round, update nonlinear terms, and compute feasibility
    for tt = -.4:0.05:0.4
        xtemp = x;xtemp(intvars) = round(xtemp(intvars)+tt);
        xtemp = min(xtemp,p.ub);
        xtemp = max(xtemp,p.lb);
        
        if ~isempty(prelaxed.binaryProduct)
            xtemp(prelaxed.binaryProduct(:,1)) = prod(xtemp(prelaxed.binaryProduct(:,2:3)),2);
        end
                
        xtemp = fix_semivar(p,xtemp);
        % Too expensive to keep doing. Perhaps
        % option on problems with problems to find feasible
        if 0
            xtemp = fix_atmost(p,xtemp,x);
            if ~isempty(prelaxed.binaryProduct)
                xtemp(prelaxed.binaryProduct(:,1)) = prod(xtemp(prelaxed.binaryProduct(:,2:3)),2);
            end
        end
        
        % Too expensive to keep doing. Perhaps
        % option on problems with problems to find feasible
        if 0
            for i = 1:length(p.downForce)
                forcing = p.downForce{i}.forcing;
                forced = p.downForce{i}.forced;
                if xtemp(forcing)==0
                    xtemp(forced)=0;
                end
            end
        end
        
        xtemp = setnonlinearvariables(p,xtemp);        
        upperhere = computecost(p.f,p.corig,p.Q,xtemp,p);
        if upperhere < upper && upperhere >= lower
            if checkfeasiblefast(p,xtemp,p.options.bnb.feastol)%res>-p.options.bnb.feastol
                x_min = xtemp;
                upper =upperhere;               
            else
                % Check for common SDP case such as maximizing smallest eigenvalue
                % or minimizing largest.                  
                % With x fixed, smallest t can be computed by gevp
                % TODO: Support and loop over several LMIs
                % Use precalculation in detectmonotoneobjectiveresponse
                if length(convars) == 1 && length(p.K.s)==1 && p.K.s(1)>0                    
                    Hy = H0 + reshape(Hz*xtemp(intvars),p.K.s(1),p.K.s(1));
                    s = eig(full(Hx),full(Hy));
                    s(isinf(s))=[];
                    s(isnan(s))=[];
                    if any(s)                             
                        xtemp(convars) = min(-1./s(s~=0));                        
                        if ~isnan(xtemp(convars))
                            xtemp(convars) = max(xtemp(convars),p.lb(convars));
                            xtemp(convars) = min(xtemp(convars),p.ub(convars));
                            upperhere = computecost(p.f,p.corig,p.Q,xtemp,p);
                            if upperhere < upper && checkfeasiblefast(p,xtemp,p.options.bnb.feastol)%res>-p.options.bnb.feastol
                                x_min = xtemp;
                                upper = upperhere;                          
                            end
                        end                    
                    end
                end
            end
        end
    end
end

if length(prelaxed.sosgroups)>0
    xtemp = x;
    stillChangable = true(length(xtemp),1);
    votes = zeros(length(xtemp),1);
    for i = 1:length(prelaxed.sosgroups)
        a = prelaxed.sosgroups{i};
        xi = x(a);
        [~,loc] = max(xi);loc = a(loc);
        votes(setdiff(a,loc)) = votes(setdiff(a,loc))-1;
        votes(loc) = votes(loc) + 1;
        stillChangable(a) = false;
    end
    for i = 1:length(prelaxed.sosgroups)
        a = prelaxed.sosgroups{i};
        [~,loc] = max(votes(a));loc = a(loc);
        xtemp(a(stillChangable(a))) = 0;
        xtemp(loc(stillChangable(loc))) = 1;
        stillChangable(a) = false;
    end
    xtemp(intvars)=round(xtemp(intvars));
    xtemp = setnonlinearvariables(p,xtemp);
    upperhere = computecost(p.f,p.corig,p.Q,xtemp,p);
    if upperhere < upper &  checkfeasiblefast(p,xtemp,p.options.bnb.feastol)
        x_min = xtemp;
        upper = upperhere;
    end
end

function x = fix_semivar(p,x);
for i = 1:length(p.semicont_variables)
    j = p.semicont_variables(i);
    if x(j)>= p.semibounds.lb(i) & x(j)<= p.semibounds.ub(i)
        % OK
    elseif x(j)==0
        % OK
    else
        s = [abs(x(j)-0); abs(x(j)-p.semibounds.lb(i));abs(x(j)-p.semibounds.ub(i))];
        [dummy,index] = min(s);
        switch index
            case 1
                x(j) = 0;
            case 2
                x(j) = p.semibounds.lb(i);
            case 3
                x(j) = p.semibounds.lb(i);
        end
    end
end

function xtemp = fix_atmost(p,xtemp,x)

would = zeros(1,length(x));
for i = 1:length(p.atmost.groups)   
    k = p.atmost.groups{i};    
    if nnz(xtemp(k))> p.atmost.bounds(i);
        n_should_be_zero = length(p.atmost.groups{i}) - p.atmost.bounds(i);
        [y,loc] = sort(abs(x(k)));
        xtemp(k(loc(1:n_should_be_zero))) = 0;
    end
end