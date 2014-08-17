%%-*-erlang-*-

-ifndef(NO_LOGGING).

%% These macros are to be used for error_logger functionality.
-define(ERRLOG(X, Y), error_logger:error_msg("[~p] "  X, [?MODULE | Y])).
-define(WARNLOG(X, Y), error_logger:warning_msg("[~p] "  X, [?MODULE | Y])).
-define(INFOLOG(X, Y), error_logger:info_msg("[~p] "  X, [?MODULE | Y])).

-else.

%% No logging version
-define(ERRLOG(_X, _Y), ok).
-define(WARNLOG(_X,_Y), ok).
-define(INFOLOG(_X, _Y), ok).

-endif. 
