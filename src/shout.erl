%%%-------------------------------------------------------------------
%%% @author <leimy2k@gmail.com>
%%% @doc
%%%  start_link(URL) connects to the stream URL and extracts
%%%  Icy metadata from the stream.  You can access the last song with
%%%  shout:get_song() which may return an empty string if no song
%%%  has been detected yet.
%%% @end
%%%------------------------------------------------------

-module(shout).

-behaviour(gen_server).

%% API
-export([start_link/1,
	 get_metadata/0]).

%% gen_server callbacks
-export([init/1, handle_call/3, handle_cast/2, handle_info/2,
	 terminate/2, code_change/3]).

-define(SERVER, ?MODULE).

-include("../include/logger.hrl").

-record(state, {metadata = [],
		stream_data = <<>>,
		metadata_interval=0
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
start_link(URL) ->
    gen_server:start_link({local, ?SERVER}, ?MODULE, [URL], [{timeout, 10000}]).

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
init([URL | _]) ->
    inets:start(),
    spawn_link(fun() -> 
		       process_flag(trap_exit, true),
		       monitor(URL) 
	       end),
    {ok, #state{}}.

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
%% handle_call(_Request, _From, State) ->
%%     Reply = ok,
%%     {reply, Reply, State}.
handle_call(reset, _From, _) ->
    {reply, ok, #state{metadata = [], stream_data = <<>>, metadata_interval=0}};

handle_call(get_metadata, _From, #state{metadata=MD}=State) ->
    {reply, {ok, MD}, State};

handle_call({examine_stream_data, BinData}, _From,
	    #state{stream_data=OldBinData, metadata_interval=Interval} = State) ->
    Concat = <<OldBinData/binary, BinData/binary>>,
    TotalSize = size(Concat),
    if 
	TotalSize >= Interval -> 
	    {_, MetaStart} = split_binary(Concat, Interval),
	    if 
		size(MetaStart) =:= 0 ->
		    {reply, ok, State#state{stream_data=Concat}};
		true ->
		    look_for_metadata_header(MetaStart, State#state{stream_data=Concat})
	    end;
	true -> {reply, ok, State#state{stream_data=Concat}}
    end;

handle_call({set_metadata_interval, Int}, _From, State) ->
    {reply, ok, State#state{metadata_interval=Int}};

handle_call(X, _, State) ->
    ?ERRLOG("Unexpected call: ~p~n", [X]),
    {stop, X, State}.

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

%%
%% This either simply concatenates the new stream data to the old and returns
%% or it reaches the interval size, and looks for metadata.
%% Looking for metadata can switch modes to the function that follows
%%


handle_cast(X, State) ->
    ?ERRLOG("Unexpected cast: ~p~n", [X]),
    {stop, X, State}.

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


%%% @private
%%% @doc
%%% The stream watcher parts (could be a separate module)
%%% @end
monitor(URL) ->
    io:format("Monitoring ~n"),
    StreamPid = spawn_link(fun stream_receiver/0),
    start_http_client(URL, StreamPid),
    receive 
	{'EXIT', StreamPid, Reason} ->
	    ?ERRLOG("Stream diedinated: ~p~n", [Reason]),
	    monitor(URL);
	X ->
	    ?INFOLOG("Shutting down because you sent me: ~p~n", [X])
    end.

%%================================================================================
%%% @private
%%% @doc
%%% Helper function to start the http client bits up.
%%% This is almost pointless and could be eliminated
%%% @end
%%================================================================================
start_http_client(URL, StreamTo) ->
    ?INFOLOG("Starting http client at: ~p streaming to pid: ~p~n", [URL, StreamTo]),
    httpc:request(get, {URL, [{"Icy-MetaData", "1"}]}, 
		  [], [{sync, false}, {full_result, true},{receiver, StreamTo},{stream, self}]).

%%================================================================================
%%% @private
%%% @doc
%%% Run in a proc, it receives stream data, and talks to the gen_server
%%% updating state as needed.  The gen_server will tear it apart and find
%%% the metadata
%%% @end
%%================================================================================
stream_receiver() ->
    receive 
	{http, {ReqID, stream_start, Headers}} ->
	    ?INFOLOG("stream start - reqid: ~p Headers: ~p~n", [ReqID, Headers]),
	    {_, IntervalString} = lists:keyfind("icy-metaint", 1, Headers),
	    {Interval, _} = string:to_integer(IntervalString),
	    gen_server:call(?MODULE, {set_metadata_interval, Interval}),
	    stream_receiver();
	{http, {ReqID, stream_end, Headers}} ->
	    gen_server:call(?MODULE, reset),
	    ?INFOLOG("stream end - reqid: ~p Header: ~p~n", [ReqID, Headers]);
	{http, {_ReqID, stream, BinData}} ->
	    gen_server:call(?MODULE, {examine_stream_data, BinData}, infinity),
	    stream_receiver();	
	{http, {ReqID, {error, Why}}} ->
	    ?ERRLOG("got an error, Reqid: ~p and I'm not happy about it: ~p~n", [ReqID, Why]);
	X ->
	    ?ERRLOG("I don't even: ~p~n", [X]),
	    init:stop()  % TODO: heavy handed perhaps
    end.
					    
%%%
%%% Friendlier API wrappers
%%%

%%================================================================================
%% @doc
%% Gets the etadata from the state in the server loop (EXPORTED)
%% @spec
%% get_metadata() -> {ok, Song}
%% @end
%%================================================================================
get_metadata() ->
    gen_server:call(?MODULE, get_metadata).

%%% CAST HELPERS
%% parse the data, and find the metadata if present.
%% if you find it, update the server state
%% If not, 
look_for_metadata_header(MetaStart, State) ->
    {NBin, Rest} = split_binary(MetaStart, 1),
    <<N:8>> = NBin,
    RestSize = size(Rest),
    RequiredSize = N * 16,
    if 
	RestSize =:= 0 ->
	    {reply, ok, State};
	RequiredSize =:= 0 ->
	    {reply, ok, State#state{stream_data=Rest}}; 
	RequiredSize =< RestSize ->
	    parse_metadata(RequiredSize, Rest, State);
	true -> 
	    {reply, ok, State}                           % need more data
    end.

%%
%% Call this when you've got enough data for sure, and skip the size byte
%%
parse_metadata(Size, Data, State) when is_binary(Data) ->
    L = binary:bin_to_list(Data),
    MetaData= [ X || X <- lists:sublist(L, Size), X =/= 0],
    Remain = binary:list_to_bin(lists:nthtail(Size, L)),
    MetaDataString = binary:list_to_bin(MetaData),
    ?INFOLOG("New metadata: ~p~n", [MetaDataString]),
    {reply, ok, State#state{metadata=MetaDataString, stream_data=Remain}}.

