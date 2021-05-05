%%%-------------------------------------------------------------------
%%% @author kapelnik
%%% @copyright (C) 2021, <COMPANY>
%%% @doc
%%%
%%% @end
%%% Created : 27. Apr 2021 3:35 AM
%%%-------------------------------------------------------------------
-module(mainGenserver).
-author("kapelnik").

-behaviour(gen_server).

%% API
-export([start_link/1]).

%% gen_server callbacks
-export([init/1, handle_call/3, handle_cast/2, handle_info/2, terminate/2,
  code_change/3]).

-define(SERVER, ?MODULE).

-record(main_genserver_state, {myName, state, clients, connectionsMap,sourcesWaitingList =[],clientsWaitingList =[]}).

%%%===============================================================

%%% API
%%%===================================================================

%% @doc Spawns the server and registers the local name (unique)
-spec(start_link(args) ->
  {ok, Pid :: pid()} | ignore | {error, Reason :: term()}).
start_link(Args) ->
  {ok,Gen_Server_Pid} = gen_server:start_link({local, ?SERVER}, ?MODULE, Args, []),
  Gen_Server_Pid.


%%%===================================================================
%%% gen_server callbacks
%%%===================================================================

%% @private
%% @doc Initializes the server
-spec(init(Args :: term()) ->
{ok, State :: #main_genserver_state{}} | {ok, State :: #main_genserver_state{}, timeout() | hibernate} |
{stop, Reason :: term()} | ignore).
init({MyName,Clients,ConnectionsMap}) ->
  inets:start(),
%%  io:format("~p~n",[ConnectionsMap]),
  start_connection(maps:to_list(ConnectionsMap)),
  {ok, #main_genserver_state{myName = MyName,state=init, clients = Clients, connectionsMap = ConnectionsMap}}.

%% @private
%% @doc Handling call messages
-spec(handle_call(Request :: term(), From :: {pid(), Tag :: term()},
    State :: #main_genserver_state{}) ->
{reply, Reply :: term(), NewState :: #main_genserver_state{}} |
{reply, Reply :: term(), NewState :: #main_genserver_state{}, timeout() | hibernate} |
{noreply, NewState :: #main_genserver_state{}} |
{noreply, NewState :: #main_genserver_state{}, timeout() | hibernate} |
{stop, Reason :: term(), Reply :: term(), NewState :: #main_genserver_state{}} |
{stop, Reason :: term(), NewState :: #main_genserver_state{}}).
handle_call(_Request, _From, State = #main_genserver_state{}) ->
{reply, ok, State}.

%% @private
%% @doc Handling cast messages
-spec(handle_cast(Request :: term(), State :: #main_genserver_state{}) ->
{noreply, NewState :: #main_genserver_state{}} |
{noreply, NewState :: #main_genserver_state{}, timeout() | hibernate} |
{stop, Reason :: term(), NewState :: #main_genserver_state{}}).


handle_cast({initCSV,ListOfSourcesClients}, State = #main_genserver_state{state = init, connectionsMap = ConnectionMap}) ->
%%  send router http request, to rout this message to all sensors
%%  TODO find the router that can send this request to Sources**
  WaitingList = findroutAndsend(ListOfSourcesClients,ConnectionMap,[]),
  io:format("WaitingList = ~p~n",[WaitingList]),
  {noreply, State#main_genserver_state{sourcesWaitingList = WaitingList}};

handle_cast({clientsTraining}, State = #main_genserver_state{state = training,clients = ListOfClients, connectionsMap = _ConnectionMap}) ->
%%  send router http request, to rout this message to all sensors
  io:format("already training~n",[]),
  {noreply, State#main_genserver_state{clientsWaitingList = ListOfClients}};

handle_cast({clientsTraining}, State = #main_genserver_state{clients = ListOfClients, connectionsMap = ConnectionMap}) ->
%%  send router http request, to rout this message to all sensors
  io:format("main server: setting all clients on training state: ~p~n",[ListOfClients]),
%%  TODO find the router that can send this request to Sources**
  [{setClientState(clientTraining,ClientName, ConnectionMap)}|| ClientName<- ListOfClients],
  {noreply, State#main_genserver_state{state = training, clientsWaitingList = ListOfClients}};

handle_cast({clientsPredict}, State = #main_genserver_state{state = predict, clients = ListOfClients, connectionsMap = ConnectionMap}) ->
%%  send router http request, to rout this message to all sensors
  io:format("already predicting~n",[]),
  {noreply, State#main_genserver_state{clientsWaitingList = ListOfClients}};

handle_cast({clientsPredict}, State = #main_genserver_state{clients = ListOfClients, connectionsMap = ConnectionMap}) ->
%%  send router http request, to rout this message to all sensors
  io:format("main server: setting all clients on clientsPredict state: ~p~n",[ListOfClients]),
%%  TODO find the router that can send this request to Sources**
  [{setClientState(clientPredict,ClientName, ConnectionMap)}|| ClientName<- ListOfClients],
  {noreply, State#main_genserver_state{state = predict, clientsWaitingList = ListOfClients}};


%%handle_cast({startPredicting}, State = #main_genserver_state{clients = ListOfClients, connectionsMap = ConnectionMap}) ->
%%%%  send router http request, to rout this message to all sensors
%%  io:format("main server: setting all clients on clientsPredict state: ~p~n",[ListOfClients]),
%%%%  TODO find the router that can send this request to Sources**
%%  [{setClientState(clientPredict,ClientName, ConnectionMap)}|| ClientName<- ListOfClients],
%%  {noreply, State#main_genserver_state{state = predict, clientsWaitingList = ListOfClients}};
%%
%%handle_cast({stopPredicting}, State = #main_genserver_state{clients = ListOfClients, connectionsMap = ConnectionMap}) ->
%%%%  send router http request, to rout this message to all sensors
%%  io:format("main server: setting all clients on clientsPredict state: ~p~n",[ListOfClients]),
%%%%  TODO find the router that can send this request to Sources**
%%  [{setClientState(clientPredict,ClientName, ConnectionMap)}|| ClientName<- ListOfClients],
%%  {noreply, State#main_genserver_state{state = predict, clientsWaitingList = ListOfClients}};


handle_cast({sourceAck,Body}, State = #main_genserver_state{sourcesWaitingList = WaitingList}) ->
  io:format("~p sent ACK~n, new sourceWaitinglist = ~p~n",[list_to_atom(binary_to_list(Body)),WaitingList--[list_to_atom(binary_to_list(Body))]]),
  {noreply, State#main_genserver_state{sourcesWaitingList = WaitingList--[list_to_atom(binary_to_list(Body))]}};

handle_cast({clientAck,Body}, State = #main_genserver_state{ clientsWaitingList = WaitingList}) ->

  io:format("~p sent ACK~n new clientWaitinglist = ~p~n",[list_to_atom(binary_to_list(Body)),WaitingList--[list_to_atom(binary_to_list(Body))]]),

  {noreply, State#main_genserver_state{clientsWaitingList = WaitingList--[list_to_atom(binary_to_list(Body))]}};

%%TODO change Client_Names to list of clients
handle_cast({startCasting,Source_Names}, State = #main_genserver_state{state = training, connectionsMap = ConnectionMap, sourcesWaitingList = [], clientsWaitingList = []}) ->
  {RouterHost,RouterPort} = maps:get(list_to_atom(binary_to_list(Source_Names)),ConnectionMap),
  http_request(RouterHost,RouterPort,"startCasting", Source_Names),
  {noreply, State};


handle_cast({startCasting,_Body}, State = #main_genserver_state{state = training, sourcesWaitingList = SourcesWaiting, clientsWaitingList = ClientsWaiting}) ->
  io:format("Waiting for ~p~n",[{SourcesWaiting, ClientsWaiting}]),
  {noreply, State};

handle_cast({startCasting,_Source_Names}, State = #main_genserver_state{state = State}) ->
  io:format("not in training state. current state- ~p~n",[State]),
  {noreply, State};


handle_cast({stopCasting,Source_Names}, State = #main_genserver_state{connectionsMap = ConnectionMap}) ->
  {RouterHost,RouterPort} = maps:get(list_to_atom(binary_to_list(Source_Names)),ConnectionMap),
  http_request(RouterHost,RouterPort,"stopCasting", Source_Names),
  {noreply, State};





handle_cast(Request, State = #main_genserver_state{}) ->

  io:format("main server cast ignored: ~p~n",[Request]),
  {noreply, State}.

%% @private
%% @doc Handling all non call/cast messages
-spec(handle_info(Info :: timeout() | term(), State :: #main_genserver_state{}) ->
{noreply, NewState :: #main_genserver_state{}} |
{noreply, NewState :: #main_genserver_state{}, timeout() | hibernate} |
{stop, Reason :: term(), NewState :: #main_genserver_state{}}).
handle_info(_Info, State = #main_genserver_state{}) ->
{noreply, State}.


%% @private
%% @doc This function is called by a gen_server when it is about to
%% terminate. It should be the opposite of Module:init/1 and do any
%% necessary cleaning up. When it returns, the gen_server terminates
%% with Reason. The return value is ignored.
-spec(terminate(Reason :: (normal | shutdown | {shutdown, term()} | term()),
    State :: #main_genserver_state{}) -> term()).
terminate(_Reason, _State = #main_genserver_state{}) ->
ok.

%% @private
%% @doc Convert process state when code is changed
-spec(code_change(OldVsn :: term() | {down, term()}, State :: #main_genserver_state{},
Extra :: term()) ->
{ok, NewState :: #main_genserver_state{}} | {error, Reason :: term()}).
code_change(_OldVsn, State = #main_genserver_state{}, _Extra) ->
{ok, State}.

%%%===================================================================
%%% Internal functions
%%%===================================================================


setClientState(clientTraining,ClientName, ConnectionMap) ->
  {RouterHost,RouterPort} =maps:get(ClientName, ConnectionMap),
  http_request(RouterHost,RouterPort,"clientTraining", atom_to_list(ClientName));

setClientState(clientPredict,ClientName, ConnectionMap) ->
  {RouterHost,RouterPort} =maps:get(ClientName, ConnectionMap),
  http_request(RouterHost,RouterPort,"clientPredict", atom_to_list(ClientName)).

%%find Router and send message: finds the path for the named machine from connection map and send to the right router to forword.
findroutAndsend([],_,WaitingList)->WaitingList;
findroutAndsend([[SourceName,ClientName,InputFile]|ListOfSources], ConnectionsMap,WaitingList) ->
  io:format("WaitingList = ~p~n~n",[WaitingList]),
  {RouterHost,RouterPort} =maps:get(list_to_atom(SourceName),ConnectionsMap),
  io:format("~p~n",[RouterPort]),
  http_request(RouterHost, RouterPort,"updateCSV", SourceName++","++ClientName++","++InputFile),
  findroutAndsend(ListOfSources,ConnectionsMap,WaitingList++[list_to_atom(SourceName)]).


%%sending Body as an http request to {Host, Port} to path Path (=String)
%%Example:  http_request(RouterHost,RouterPort,"start_training", <<"client1,client2">>),
http_request(Host, Port,Path, Body)->
  httpc:request(post,{"http://" ++ Host ++ ":"++integer_to_list(Port) ++ "/" ++ Path, [],"application/x-www-form-urlencoded",Body}, [], []).


%%Receives a list of routers and connects to them
start_connection([])->ok;
start_connection([{_ServerName,{Host, Port}}|Tail]) ->
  httpc:set_options([{proxy, {{Host, Port},[Host]}}]),
  start_connection(Tail).