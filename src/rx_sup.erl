%%%-------------------------------------------------------------------
%%% @author David Leimbach <leimy2k@gmail.com>
%%% @copyright (C) 2014, David Leimbach
%%% @doc
%%%
%%% @end
%%% Created : 16 Aug 2014 by David Leimbach 
%%%-------------------------------------------------------------------
-module(rx_sup).

-behaviour(supervisor).

%% API
-export([
	 start_link/0, 
	 start/0,
	 start_in_shell_for_testing/0
	]).
-include("../include/logger.hrl").

%% Supervisor callbacks
-export([init/1]).

-define(SERVER, ?MODULE).

%%%===================================================================
%%% API functions
%%%===================================================================

start() ->
    spawn(fun() ->
		  supervisor:start_link({local, ?MODULE}, ?MODULE, 
					_Arg = [])
	  end).


start_in_shell_for_testing() ->
    {ok, Pid} = supervisor:start_link({local, ?MODULE}, ?MODULE, _Arg = []),
    unlink(Pid).	

%%--------------------------------------------------------------------
%% @doc
%% Starts the supervisor
%%
%% @spec start_link() -> {ok, Pid} | ignore | {error, Error}
%% @end
%%--------------------------------------------------------------------
start_link() ->
    supervisor:start_link({local, ?SERVER}, ?MODULE, []).

%%%===================================================================
%%% Supervisor callbacks
%%%===================================================================

-define(MAXRESTARTS, 3).
-define(SECONDS, 10).
-define(MAXTERMINATE, brutal_kill).

%%--------------------------------------------------------------------
%% @private
%% @doc
%% Whenever a supervisor is started using supervisor:start_link/[2,3],
%% this function is called by the new process to find out about
%% restart strategy, maximum restart frequency and child
%% specifications.
%%
%% @spec init(Args) -> {ok, {SupFlags, [ChildSpec]}} |
%%                     ignore |
%%                     {error, Reason}
%% @end
%%--------------------------------------------------------------------
init([]) ->
    ?INFOLOG("~p starting", [?MODULE]),
    {ok, {{one_for_all, 0, ?SECONDS}, 
	  [
	   {bot_tag,
	    {bot, start_link, [["irc.radioxenu.com", 6667, "MetaBot3", "#radioxenu"]]},
	    permanent,
	    ?MAXTERMINATE,
	    worker,
	    [bot]},
	   {shout_tag,
	    {shout, start_link, ["http://www.radioxenu.com:8000/relay"]},
	    permanent,
	    ?MAXTERMINATE, 
	    worker,
	    [shout]}
	   ]}}.

%%%===================================================================
%%% Internal functions
%%%===================================================================
