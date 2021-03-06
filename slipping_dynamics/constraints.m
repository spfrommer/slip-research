function [ c, ceq ] = constraints( funparams, sp )
    % Phase inequality constraints
    phaseIC = sym('pic', [1, 4*sp.gridn*size(sp.phases, 1)])';
     
    % Phase equality constraints
    phaseEC = sym('pec', [1, 8*(sp.gridn-1)*size(sp.phases, 1)])';
    % Phase transition equality constraints
    transEC = sym('tec', [1, 8*(size(sp.phases, 1)-1)])';
    
    % Unpack the parameter vector
    [ stanceT, flightT, xtoe, xtoedot, x, xdot, y, ydot, ...
           ra, radot, raddot, torque] = unpack(funparams, sp);
    
    % Iterate over all the phases
    for p = 1 : size(sp.phases, 1)
        phaseStr = sp.phases(p, :);
        % The index of the first dynamics variable for the current phase
        ps = (p - 1) * sp.gridn + 1;
        
        % Calculate the timestep for that specific phase
        dt = stanceT(p) / sp.gridn;
        
        % Take off state at the end of the last phase
        if p > 1
            toState = stateN;
            toAuxvars = auxvarsN;
        end
        
        stateN = [xtoe(ps); xtoedot(ps); x(ps);  xdot(ps);   ...
                  y(ps);    ydot(ps);    ra(ps); radot(ps)];
        
        % Link ballistic trajectory from end of last phase to this phase
        if p > 1
            rland = sqrt((x(ps) - xtoe(ps))^2 + y(ps)^2);
            
            [xtoedotland, xland, xdotland, yland, ydotland] = ...
                ballistic(toState, flightT(p-1), phaseStr, sp);
            % Grf must equal zero at takeoff
            transEC((p-2)*8+1 : (p-1)*8) = ...
                    [xtoedotland-xtoedot(ps); xland-x(ps); ...
                    xdotland-xdot(ps); yland-y(ps); ydotland-ydot(ps); ...
                    ra(ps) - rland; radot(ps); toAuxvars.grf];
        end
            
        % Offset in the equality parameter vector due to phase
        pecOffset = 8 * (sp.gridn - 1) * (p - 1);
        % Offset in the inequality parameter vector due to phase
        picOffset = 4 * (sp.gridn) * (p - 1);
        
        [statedotN, auxvarsN] = dynamics(stateN, raddot(ps), ...
                                          torque(ps), sp, phaseStr);
        for i = 1 : sp.gridn - 1
            % The state at the beginning of the time interval
            stateI = stateN;
            % What the state should be at the end of the time interval
            stateN = [xtoe(ps+i); xtoedot(ps+i); x(ps+i);  xdot(ps+i); ...
                      y(ps+i);    ydot(ps+i);    ra(ps+i); radot(ps+i)];
            % The state derivative at the beginning of the time interval
            statedotI = statedotN;
            % Some calculated variables at the beginning of the interval
            auxvarsI = auxvarsN;
            % The state derivative at the end of the time interval
            [statedotN, auxvarsN] = ...
                dynamics(stateN, raddot(ps+i), torque(ps+i), sp, phaseStr);

            % The end position of the time interval calculated using quadrature
            endState = stateI + dt * (statedotI + statedotN) / 2;
            
            % Constrain the end state of the current time interval to be
            % equal to the starting state of the next time interval
            phaseEC(pecOffset+(i-1)*8+1:pecOffset+i*8) = stateN - endState;
            % Constrain the length of the leg, grf, and body y pos
            phaseIC(picOffset+(i-1)*4+1 : picOffset+i*4) = ...
                    [auxvarsI.r - sp.maxlen; sp.minlen - auxvarsI.r; ...
                     -auxvarsI.grf; auxvarsI.grf - sp.maxgrf];
        end
        
        if p == size(sp.phases, 1)
            % Constrain the length of the leg at the end position
            % Since it's the end of the last phase, add grf constraint
            phaseIC(picOffset+(sp.gridn-1)*4+1:picOffset+sp.gridn*4) = ...
                [auxvarsN.r - sp.maxlen; sp.minlen - auxvarsN.r; ...
                -auxvarsN.grf; auxvarsN.grf - sp.maxgrf];
        else 
            % Constrain the length of the leg at the end position
            % No ground reaction force constraint (this will be handled in
            % transition equality constraints)
            phaseIC(picOffset+(sp.gridn-1)*4+1:picOffset+sp.gridn*4) = ...
                [auxvarsN.r - sp.maxlen; sp.minlen - auxvarsN.r; -1; -1];
        end
    end
    
    c = phaseIC;
    ceq = [phaseEC; transEC];
    
    initialState = [xtoe(1); xtoedot(1); x(1);  xdot(1);   ...
                  y(1);    ydot(1);    ra(1); radot(1)];
              
    % Add first phase start constraints
    ceq = [ceq; initialState - sp.initialState];
    % Add last phase end constraints
    ceq = [ceq; x(end) - sp.finalProfileX; xtoe(end) - sp.finalProfileX];
end