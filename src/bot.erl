%%%-------------------------------------------------------------------
%%% @author <leimy2k@gmail.com>
%%% @doc
%%%
%%% @end
%%% Created : 15 Aug 2014 by David Leimbach <dleimbach@isilon.com>
%%%-------------------------------------------------------------------
-module(bot).
-include("../include/logger.hrl").
-behaviour(gen_server).

%% API
-export([start_link/1]).

%% gen_server callbacks
-export([init/1, handle_call/3, handle_cast/2, handle_info/2,
	 terminate/2, code_change/3]).

-define(SERVER, ?MODULE).

-record(state, {sock=none,
		channel="",
		nick=""
	       }).

%%%===================================================================
%%% API
%%%===================================================================

%%--------------------------------------------------------------------
%% @doc
%% Starts the server
%%
%% @spec start_link() -> {ok, Pid} | ignore | {error, Error}
%% @end
%%--------------------------------------------------------------------
start_link(Args) ->
    ?INFOLOG("Args: ~p~n", [Args]),
    gen_server:start_link({local, ?SERVER}, ?MODULE, Args, [{timeout, 10000}]).

%%%===================================================================
%%% gen_server callbacks
%%%===================================================================

%%--------------------------------------------------------------------
%% @private
%% @doc
%% Initializes the server
%%
%% @spec init(Args) -> {ok, State} |
%%                     {ok, State, Timeout} |
%%                     ignore |
%%                     {stop, Reason}
%% @end
%%--------------------------------------------------------------------
init([IRCServer, Port, Nick, Channel | _]) ->
    spawn_link(fun() ->
		       setup_and_receive(IRCServer, Port, Nick, Channel)
	       end),
    {ok, #state{channel=Channel,
		nick=Nick}}.

%%--------------------------------------------------------------------
%% @private
%% @doc
%% Handling call messages
%%
%% @spec handle_call(Request, From, State) ->
%%                                   {reply, Reply, State} |
%%                                   {reply, Reply, State, Timeout} |
%%                                   {noreply, State} |
%%                                   {noreply, State, Timeout} |
%%                                   {stop, Reason, Reply, State} |
%%                                   {stop, Reason, State}
%% @end
%%--------------------------------------------------------------------
handle_call({set_sock, Sock}, _From, State) ->
    {reply, ok, State#state{sock=Sock}};

handle_call({parse_binary, Bin}, _From, #state{sock=Sock, channel=Channel}=State) ->
    Rest = parse_bin(Sock, Channel, Bin),
    {reply, {ok, Rest}, State};

handle_call(_Request, _From, State) ->
    {stop, "Wwhat!?! I'm done", State}.


%%--------------------------------------------------------------------
%% @private
%% @doc
%% Handling cast messages
%%
%% @spec handle_cast(Msg, State) -> {noreply, State} |
%%                                  {noreply, State, Timeout} |
%%                                  {stop, Reason, State}
%% @end
%%--------------------------------------------------------------------
handle_cast(_Msg, State) ->
    {noreply, State}.

%%--------------------------------------------------------------------
%% @private
%% @doc
%% Handling all non call/cast messages
%%
%% @spec handle_info(Info, State) -> {noreply, State} |
%%                                   {noreply, State, Timeout} |
%%                                   {stop, Reason, State}
%% @end
%%--------------------------------------------------------------------
handle_info(_Info, State) ->
    {noreply, State}.

%%--------------------------------------------------------------------
%% @private
%% @doc
%% This function is called by a gen_server when it is about to
%% terminate. It should be the opposite of Module:init/1 and do any
%% necessary cleaning up. When it returns, the gen_server terminates
%% with Reason. The return value is ignored.
%%
%% @spec terminate(Reason, State) -> void()
%% @end
%%--------------------------------------------------------------------
terminate(_Reason, _State) ->
    ok.

%%--------------------------------------------------------------------
%% @private
%% @doc
%% Convert process state when code is changed
%%
%% @spec code_change(OldVsn, State, Extra) -> {ok, NewState}
%% @end
%%--------------------------------------------------------------------
code_change(_OldVsn, State, _Extra) ->
    {ok, State}.

%%%===================================================================
%%% Internal functions
%%%===================================================================

setup_and_receive(IRCServer, Port, Nick, Channel) ->
    {ok, Sock} = gen_tcp:connect(IRCServer, Port, [binary, {packet, 0}]),
    ?INFOLOG("Connected, logging on", []),
    gen_server:call(?MODULE, {set_sock, Sock}, infinity),
    ok = gen_tcp:send(Sock, "NICK " ++ Nick ++ " \r\n"), 
    ok = gen_tcp:send(Sock, "USER " ++ Nick ++ " 0 * :tutorial bot\r\n"), 
    ok = gen_tcp:send(Sock, "JOIN " ++ Channel ++ "\r\n"), 
    receive_loop(Sock, <<>>),
    setup_and_receive(IRCServer, Port, Nick, Channel).

%%================================================================================
%% @private
%% @doc
%% The receive loop for the bot.
%%================================================================================
receive_loop(Sock, SoFar) ->
    receive 
	{tcp, Sock, Bin} ->
	    ConcatBin = if
			    size(SoFar) > 0 -> 
				<<SoFar/binary, Bin/binary>>;
			    true -> Bin
			end,		
	    {ok,Rest} = gen_server:call(?MODULE, {parse_binary, ConcatBin}, infinity),
	    receive_loop(Sock, Rest);
	{tcp_closed, Sock} ->
	    ?ERRLOG("Socket closed", []);
	X ->
	    ?ERRLOG("No idea what this is: ~p",[X])
    end.

%%================================================================================
%% @private
%% @doc
%% Given a binary, split into lines and if there are any, deal with it
%% Return the unused portion
%%================================================================================
parse_bin(Sock, Channel, Bin) ->
    {Lines, Rest} = get_lines(Bin),
    lists:map(fun(X) ->
		      deal_with_it(Sock, Channel, X) 
	      end, Lines),
    Rest.

%%================================================================================
%% @private
%% @doc
%% Given a Binary, finds all runs of bytes containing the sequence CR LF, and 
%% returns them as a list of lists along with the remainder of the Binary if
%% there are no matches
%%================================================================================
get_lines(Bin) ->
    {Pos, Lines, _} = lists:foldl(
		     fun({Pos,_}, {Last, AccList, Const}) ->
			     Submatch = binary:bin_to_list(binary:part(
							     Const, 
							     {Last, Pos-Last})),
			     {Pos + 2, AccList ++ [Submatch], Const}
		     end,  
		     {0, [], Bin}, 
		     binary:matches(Bin, <<13,10>>)),
    {_, Rest} = split_binary(Bin, Pos),
    {Lines, Rest}.

%%================================================================================
%% @private
%% @doc
%% Strip out color, break up the line to determine what's going on, and then do
%% stuff about it.  deal_with_it is a good choice for the gen_server
%%================================================================================
deal_with_it(Sock, Channel, Line) ->
    TNs = string:tokens(strip_color_and_ctcp(Line), " "),   
    do_it(Sock, Channel, TNs).

%%================================================================================
%% @private
%% @doc
%% Action handlers...
%%================================================================================
do_it(Sock, _Chan, ["PING" | Rest]) ->
    gen_tcp:send(Sock, string:join(["PONG",Rest++[13,10]], " "));

do_it(Sock, Channel, [User, "PRIVMSG", Channel, ":?lastsong?" | _]) ->    
    {ok, MetaBin} = shout:get_metadata(),
    {Artist, Song} = parse_artist_and_song(MetaBin),
    NickResp = parse_resp_user(User),
    S = io_lib:format("PRIVMSG ~s :~s, the last song playing I know of is: ~s by ~s~s", [Channel, NickResp, Song, Artist, [13,10]]),
    gen_tcp:send(Sock, S);

do_it(_S, _C, _Stuff) -> 
    ?INFOLOG("Unhandled: ~p", [_Stuff]),
    ok.

parse_resp_user(User) ->		      
    [NickResp | _] = string:tokens(string:substr(User, 2), "!"),
    NickResp.

parse_artist_and_song(MetaBin) ->
    MetaString = binary:bin_to_list(MetaBin),
    Sub = lists:nth(2, string:tokens(MetaString, "'")),
    list_to_tuple(lists:map(fun(X) -> string:strip(X) end, string:tokens(Sub, "-"))).    
    
%%================================================================================
%% @private
%% @doc
%% Colors in IRC appear to be a byte sequence of <<3>> folowed by the ASCII
%% representation of a color selector.  We don't care about this at all (though
%% we may want to generate them later).  When we're interpreting commands, we
%% don't want that data.  Strip it out.
%%================================================================================
strip_color_and_ctcp(String) ->
    {_, Res} = lists:foldl(
		 fun(X, {Last, Accum}) ->
			 if 
			     X =:= 1 -> {false, Accum};
			     Last -> {false, Accum};  
			     X =:= 3 -> {true, Accum};
			     true -> {false, Accum ++ [X]}
			 end
		 end, {false, []}, String),
    Res.


		      
    
