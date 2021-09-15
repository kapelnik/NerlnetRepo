%%%-------------------------------------------------------------------
%%% @author kapelnik
%%% @copyright (C) 2021, <COMPANY>
%%% @doc
%%%
%%% @end
%%% Created : 14. Apr 2021 9:57 AM
%%%-------------------------------------------------------------------
-module(clientStatem).
-author("kapelnik").

-behaviour(gen_statem).

%%-import('nerlNetStatem', []).
%%-import('../../erlBridge/nerlNetStatem', []).

%% API
-export([start_link/1, predict/3]).

%% gen_statem callbacks
-export([init/1, format_status/2, state_name/3, handle_event/4, terminate/3,
  code_change/4, callback_mode/0, idle/3, training/3]).

-define(SERVER, ?MODULE).

-record(client_statem_state, {myName, federatedServer,workersMap, portMap, msgCounter}).


%%%===================================================================
%%% API
%%%===================================================================

%% @doc Creates a gen_statem process which calls Module:init/1 to
%% initialize. To ensure a synchronized start-up procedure, this
%% function does not return until Module:init/1 has returned.

%%Arguments from Cowboy Server
%%return gen_statem's Pid to Cowboy Server
%%Client_StateM_Args= {self(),RouterPort},
start_link(Args) ->
    {ok,Pid} = gen_statem:start_link(?MODULE, Args, []),
    Pid.

%%%===================================================================
%%% gen_statem callbacks
%%%===================================================================

%% @private
%% @doc Whenever a gen_statem is started using gen_statem:start/[3,4] or
%% gen_statem:start_link/[3,4], this function is called by the new
%% process to initialize.
%%initialize and go to state - idle


%%NerlClientsArgs=[{MyName,Workers,ConnectionsMap},...], Workers = list of maps of name and args
%%  init nerlClient with given workers and parameters, and build a map :#{workerName=>WorkerPid,...}
init({MyName,Federated,Workers,ConnectionsMap}) ->
  inets:start(),
  start_connection(maps:to_list(ConnectionsMap)),
%% io:format("~p~n",[maps:to_list(Workers)]),
  WorkersPids = createWorkers(Workers,self(),[]),
%%  [{WorkerName,nerlNetStatem:start_link({self(), WorkerName, CppSANNArgs})}||{WorkerName,CppSANNArgs}<-maps:to_list(Workers)],
  WorkersMap = maps:from_list(WorkersPids),

%%TODO workers = WorkersMap <-TODO ADD
  {ok, idle, #client_statem_state{myName= MyName,federatedServer = Federated, workersMap = WorkersMap, portMap = ConnectionsMap, msgCounter = 1}}.

createWorkers([],_ClientPid,WorkersNamesPids) ->WorkersNamesPids;
createWorkers([Worker|Workers],ClientPid,WorkersNamesPids) ->
  WorkerName = list_to_atom(binary_to_list(maps:get(<<"name">>,Worker))),
  CppSANNArgsBinary = maps:get(<<"args">>,Worker),
  Splitted = re:split(CppSANNArgsBinary,"@",[{return,list}]),
  [Layers_sizes, Learning_rate, ActivationList, Optimizer, ModelId, Features, Labels] = Splitted,
  % TODO receive from JSON
FederatedMode="1", CountLimit="10",
  % TODO receive from JSON

  WorkerArgs ={string_to_list_int(Layers_sizes),list_to_float(Learning_rate),
                  string_to_list_int(ActivationList), list_to_integer(Optimizer), list_to_integer(ModelId),
                      list_to_integer(Features), list_to_integer(Labels),list_to_integer(FederatedMode), list_to_integer(CountLimit)},
  io:format("client starting worker:~p~n",[{WorkerName,WorkerArgs}]),
  WorkerPid = nerlNetStatem:start_link({self(), WorkerName, WorkerArgs}),
  createWorkers(Workers,ClientPid,WorkersNamesPids++[{WorkerName, WorkerPid}]).

%%return list of integer from string of lists of strings - "[2,2,2]" -> [2,2,2]
string_to_list_int(String) ->
  NoParenthesis = lists:sublist(String,2,length(String)-2),
  Splitted = re:split(NoParenthesis,",",[{return,list}]),
  [list_to_integer(X)||X<-Splitted].
%% @private
%% @doc This function is called by a gen_statem when it needs to find out
%% the callback mode of the callback module.
callback_mode() ->
  state_functions.

%% @private
%% @doc Called (1) whenever sys:get_status/1,2 is called by gen_statem or
%% (2) when gen_statem terminates abnormally.
%% This callback is optional.
format_status(_Opt, [_PDict, _StateName, _State]) ->
  Status = some_term,
  Status.

%% @private
%% @doc There should be one instance of this function for each possible
%% state name.  If callback_mode is state_functions, one of these
%% functions is called when gen_statem receives and event from
%% call/2, cast/2, or as a normal process message.
state_name(_EventType, _EventContent, State = #client_statem_state{}) ->
  NextStateName = next_state,
  {next_state, NextStateName, State}.



%%initiating nerlnet, given parameters in Body received by Cowboy init_handler
idle(cast, {init,CONFIG}, State = #client_statem_state{msgCounter = Counter}) ->
  % io:format("initiating, CONFIG received:~p ~n",[CONFIG]),
  {next_state, idle, State#client_statem_state{msgCounter = Counter+1}};

idle(cast, {statistics}, State = #client_statem_state{ myName = MyName,msgCounter = Counter,portMap = PortMap}) ->
  {RouterHost,RouterPort} = maps:get(mainServer,PortMap),
  http_request(RouterHost,RouterPort,"statistics", list_to_binary(atom_to_list(MyName)++"#"++integer_to_list(Counter))),
  {next_state, idle, State#client_statem_state{msgCounter = Counter+1}};

idle(cast, {training}, State = #client_statem_state{workersMap = WorkersMap, myName = MyName,msgCounter = Counter,portMap = PortMap}) ->
  Workers = maps:to_list(WorkersMap),
  [gen_statem:cast(WorkerPid,{training})|| {_WorkerName,WorkerPid}<-Workers],
%%  io:format("sending ACK   ~n",[]),
%%  {RouterHost,RouterPort} = maps:get(mainServer,PortMap),
%%  send an ACK to mainserver that the CSV file is ready
  ack(MyName,PortMap),
  {next_state, training, State#client_statem_state{msgCounter = Counter+1}};

idle(cast, {predict}, State = #client_statem_state{workersMap = WorkersMap,myName = MyName,msgCounter = Counter,portMap = PortMap}) ->
  io:format("client going to state predict",[]),
  Workers = maps:to_list(WorkersMap),
  [gen_statem:cast(WorkerPid,{predict})|| {_WorkerName,WorkerPid}<-Workers],
  %%  send an ACK to mainserver that the CSV file is ready
  ack(MyName,PortMap),
  {next_state, predict, State#client_statem_state{msgCounter = Counter+1}};

idle(cast, EventContent, State = #client_statem_state{msgCounter = Counter}) ->
  %io:format("client training ignored:  ~p ~n",[EventContent]),
  {next_state, training, State#client_statem_state{msgCounter = Counter+1}}.


training(cast, {sample,[]}, State = #client_statem_state{msgCounter = Counter}) ->

  io:format("client go empty Vector~n",[]),

  {next_state, training, State#client_statem_state{msgCounter = Counter+1}};

training(cast, {sample,Vector}, State = #client_statem_state{msgCounter = Counter,workersMap = WorkersMap}) ->
  %%    Body:   ClientName#WorkerName#CSVName#BatchNumber#BatchOfSamples
  [_ClientName,WorkerName,_CSVName, _BatchNumber,BatchOfSamples] = re:split(binary_to_list(Vector), "#", [{return, list}]),
  Splitted = re:split(BatchOfSamples, ",", [{return, list}]),
  ToSend =  lists:reverse(getNumbers(Splitted,[])),
%%  io:format("BatchNumber: ~p~n",[BatchNumber]),
%%  io:format("WorkerName: ~p~n",[WorkerName]),
  WorkerPid = maps:get(list_to_atom(WorkerName),WorkersMap),
  gen_statem:cast(WorkerPid, {sample,ToSend}),
  {next_state, training, State#client_statem_state{msgCounter = Counter+1}};

training(cast, {idle}, State = #client_statem_state{workersMap = WorkersMap,msgCounter = Counter}) ->
  io:format("client going to state idle",[]),
  Workers = maps:to_list(WorkersMap),
  [gen_statem:cast(WorkerPid,{idle})|| {_WorkerName,WorkerPid}<-Workers],
  {next_state, idle, State#client_statem_state{msgCounter = Counter+1}};

training(cast, {predict}, State = #client_statem_state{workersMap = WorkersMap,myName = MyName, portMap = PortMap, msgCounter = Counter}) ->
  io:format("client going to state predict",[]),
  Workers = maps:to_list(WorkersMap),
  [gen_statem:cast(WorkerPid,{predict})|| {_WorkerName,WorkerPid}<-Workers],
  ack(MyName,PortMap),
  {next_state, predict, State#client_statem_state{msgCounter = Counter+1}};

training(cast, {loss,WorkerName,nan}, State = #client_statem_state{myName = MyName,portMap = PortMap,  msgCounter = Counter}) ->
%%   io:format("LossFunction1: ~p   ~n",[LossFunction]),
  {RouterHost,RouterPort} = maps:get(mainServer,PortMap),
  http_request(RouterHost,RouterPort,"lossFunction", list_to_binary([list_to_binary(atom_to_list(WorkerName)),<<"#">>,<<"nan">>])),
  {next_state, training, State#client_statem_state{msgCounter = Counter+1}};

training(cast, {loss,WorkerName,LossFunction}, State = #client_statem_state{myName = MyName,portMap = PortMap,  msgCounter = Counter}) ->
   io:format("LossFunction1: ~p   ~n",[LossFunction]),
  {RouterHost,RouterPort} = maps:get(mainServer,PortMap),
  http_request(RouterHost,RouterPort,"lossFunction", list_to_binary([list_to_binary(atom_to_list(WorkerName)),<<"#">>,float_to_binary(LossFunction)])),
  {next_state, training, State#client_statem_state{msgCounter = Counter+1}};



%%Federated Mode:
training(cast, {loss,federated_weights, Worker, LOSS_FUNC, Ret_weights}, State = #client_statem_state{federatedServer = Federated,myName = MyName,portMap = PortMap,  msgCounter = Counter}) ->
%%  io:format("Worker: ~p~n, LossFunction: ~p~n,  Ret_weights_tuple: ~p~n",[Worker, LOSS_FUNC, Ret_weights_tuple]),
  {RouterHost,RouterPort} = maps:get(Federated,PortMap),
  % io:format("sending weights :~p~n",[Ret_weights]),
  % io:format("sending weights binary :~p~n",[list_to_binary(Ret_weights)]),
%%  ToSend = list_to_binary([list_to_binary(atom_to_list(Federated)),<<"#">>,list_to_binary(Ret_weights)]),

%%  TODO when ziv changes from string to list of lists remove this
%%  Ret_weights2 = [[1.1,2.2],[3.3,4.4],[1,2],[2,3]],
%%  io:format("Ret_weights: ~n~p~n",[Ret_weights]),

  ToSend = term_to_binary({Federated,encodeListOfLists(Ret_weights)}),

%%  io:format("ToSend: ~p~n, ",[ToSend]),
%%  io:format("ToSend: ~p~n, ",[ToSend]),
%%["1.002,"30.2","2.1"]
  http_request(RouterHost,RouterPort,"federatedWeightsVector", ToSend),
%%  TODO send federated_weights to federated_server
  {next_state, training, State#client_statem_state{msgCounter = Counter+1}};

training(cast, {loss, federated_weights, MyName, LOSS_FUNC}, State = #client_statem_state{myName = MyName,portMap = PortMap,  msgCounter = Counter}) ->
  % io:format("MyName: ~p~n, LossFunction2: ~p~n",[MyName, LOSS_FUNC]),
%%  {RouterHost,RouterPort} = maps:get(mainServer,PortMap),
%%  TODO send federated_weights to federated_server
  {next_state, training, State#client_statem_state{msgCounter = Counter+1}};

training(cast, {federatedAverageWeights,Body}, State = #client_statem_state{myName = MyName,portMap = PortMap,workersMap = WorkersMap, msgCounter = Counter}) ->
%% io:format("federatedAverageWeights Body!!!!: ~p~n",[Body]),
  {ClientName,WorkerName,BinaryWeights} = binary_to_term(Body),

%%  [_ClientName,WorkerName,Weights] = re:split(binary_to_list(Body),"#",[{return,list}]),
  WorkerPid = maps:get(WorkerName,WorkersMap),
  io:format("client decoding weights!!!:   ~n!!!",[]),

  DecodedWeights = decodeListOfLists(BinaryWeights),
  io:format("client finished decoding weights!!!:   ~n!!!",[]),
  gen_statem:cast(WorkerPid, {set_weights,  DecodedWeights}),
%%  {RouterHost,RouterPort} = maps:get(mainServer,PortMap),
%%  TODO send federated_weights to federated_server
  {next_state, training, State#client_statem_state{msgCounter = Counter+1}};

training(cast, EventContent, State = #client_statem_state{msgCounter = Counter}) ->
  io:format("client training ignored!!!:  ~p ~n!!!",[EventContent]),
  {next_state, training, State#client_statem_state{msgCounter = Counter+1}}.


predict(cast, {sample,Body}, State = #client_statem_state{msgCounter = Counter,workersMap = WorkersMap}) ->
  %%    Body:   ClientName#WorkerName#CSVName#BatchNumber#BatchOfSamples
  [_ClientName,WorkerName,CSVName, BatchNumber,BatchOfSamples] = re:split(binary_to_list(Body), "#", [{return, list}]),
  Splitted = re:split(BatchOfSamples, ",", [{return, list}]),
  ToSend =  lists:reverse(getNumbers(Splitted,[])),
%%  io:format("CSVName: ~p, BatchNumber: ~p~n",[CSVName,BatchNumber]),
%%  io:format("Vector: ~p~n",[ToSend]),
  WorkerPid = maps:get(list_to_atom(WorkerName),WorkersMap),
  gen_statem:cast(WorkerPid, {sample,CSVName, BatchNumber,ToSend}),
%%  gen_statem:cast(WorkerPid, {sample,ToSend}),
  {next_state, predict, State#client_statem_state{msgCounter = Counter+1}};

predict(cast, {predictRes,_InputName,_ResultID,[]}, State) ->
  {next_state, predict, State};

predict(cast, {predictRes,InputName,ResultID,Result}, State = #client_statem_state{msgCounter = Counter,portMap = PortMap}) ->
  %io:format("Client got result from predict-~nInputName: ~p,ResultID: ~p, ~nResult:~p~n",[InputName,ResultID,Result]),
  {RouterHost,RouterPort} = maps:get(mainServer,PortMap),
  Result2 = lists:flatten(io_lib:format("~w",[Result])),",",[{return,list}],
  Result3 = lists:sublist(Result2,2,length(Result2)-2),
  http_request(RouterHost,RouterPort,"predictRes", list_to_binary([list_to_binary(InputName),<<"#">>,ResultID,<<"#">>,Result3])),
  {next_state, predict, State#client_statem_state{msgCounter = Counter+1}};

predict(cast, {training}, State = #client_statem_state{workersMap = WorkersMap,myName = MyName,portMap = PortMap,msgCounter = Counter}) ->
  Workers = maps:to_list(WorkersMap),
  [gen_statem:cast(WorkerPid,{training})|| {_WorkerName,WorkerPid}<-Workers],
  ack(MyName,PortMap),
  {next_state, training, State#client_statem_state{msgCounter = Counter+1}};

predict(cast, {idle}, State = #client_statem_state{workersMap = WorkersMap,msgCounter = Counter}) ->
  Workers = maps:to_list(WorkersMap),
  [gen_statem:cast(WorkerPid,{idle})|| {_WorkerName,WorkerPid}<-Workers],
  io:format("client going to state idle~n",[]),
  {next_state, idle, State#client_statem_state{msgCounter = Counter+1}};

predict(cast, EventContent, State = #client_statem_state{msgCounter = Counter}) ->
  io:format("client predict ignored:  ~p ~n",[EventContent]),
  {next_state, predict, State#client_statem_state{msgCounter = Counter+1}}.


%% @private
%% @doc If callback_mode is handle_event_function, then whenever a
%% gen_statem receives an event from call/2,  cast/2, or as a normal
%% process message, this function is called.
handle_event(_EventType, _EventContent, _StateName, State = #client_statem_state{}) ->
  NextStateName = the_next_state_name,
  {next_state, NextStateName, State}.

%% @private
%% @doc This function is called by a gen_statem when it is about to
%% terminate. It should be the opposite of Module:init/1 and do any
%% necessary cleaning up. When it returns, the gen_statem terminates with
%% Reason. The return value is ignored.
terminate(_Reason, _StateName, _State = #client_statem_state{}) ->
  ok.

%% @private
%% @doc Convert process state when code is changed
code_change(_OldVsn, StateName, State = #client_statem_state{}, _Extra) ->
  {ok, StateName, State}.

%%%===================================================================
%%% Internal functions
%%%===================================================================
start_connection([])->ok;
start_connection([{_ServerName,{Host, Port}}|Tail]) ->
  httpc:set_options([{proxy, {{Host, Port},[Host]}}]),
  start_connection(Tail).

http_request(Host, Port,Path, Body)->
%%  io:format("sending body ~p to path ~p to hostport:~p~n",[Body,Path,{Host,Port}]),
  URL = "http://" ++ Host ++ ":"++integer_to_list(Port) ++ "/" ++ Path,
  httpc:set_options([{proxy, {{Host, Port},[Host]}}]),
  httpc:request(post,{URL, [],"application/x-www-form-urlencoded",Body}, [], []).


ack(MyName, PortMap) ->
    io:format("~p sending ACK   ~n",[MyName]),
  {RouterHost,RouterPort} = maps:get(mainServer,PortMap),
%%  send an ACK to mainserver that the CSV file is ready
  http_request(RouterHost,RouterPort,"clientReady",atom_to_list(MyName)).

getNumbers([],List)->List;
getNumbers([[]|Tail], List) -> getNumbers(Tail,List);
getNumbers([Head|Tail], List) ->
%%  io:format("Head:~p~n",[Head]),

  try list_to_float(Head) of
    Float->    %io:format("~p~n",[Float]),
      getNumbers(Tail,[(Float)]++List)
  catch
    error:_Error->
      %io:format("~p~n",[Error]),
      getNumbers(Tail,[list_to_integer(Head)]++List)

  end.

encode(Ret_weights_tuple)->
  {Weights,Bias,Biases_sizes_list,Wheights_sizes_list} = Ret_weights_tuple,
  ToSend =   list_to_binary(Weights) ++ <<"#">> ++ list_to_binary(Bias) ++ <<"@">> ++ list_to_binary(Biases_sizes_list) ++ <<"@">>  ++ list_to_binary(Wheights_sizes_list),
  % io:format("ToSend  ~p",[ToSend]),
    ToSend.
%%  Weights ++ <<"@">> ++ Bias ++ <<"@">> ++ [Biases_sizes_list] ++ <<"@">>  ++ Wheights_sizes_list.

%%This encoder receives a lists of lists: [[1.0,1.1,11.2],[2.0,2.1,22.2]] and returns a binary
encodeListOfLists(L)->encodeListOfLists(L,[]).
encodeListOfLists([],Ret)->term_to_binary(Ret);
encodeListOfLists([H|T],Ret)->encodeListOfLists(T,Ret++[encodeFloatsList(H)]).
encodeFloatsList(ListOfFloats)->
  ListOfBinaries = [<<X:64/float>>||X<-ListOfFloats],
  list_to_binary(ListOfBinaries).

%%This decoder receives a binary <<131,108,0,0,0,2,106...>> and returns a lists of lists: [[1.0,1.1,11.2],[2.0,2.1,22.2]]
decodeListOfLists(L)->decodeListOfLists(binary_to_term(L),[]).
decodeListOfLists([],Ret)->Ret;
decodeListOfLists([H|T],Ret)->decodeListOfLists(T,Ret++[decodeList(H)]).
decodeList(Binary)->  decodeList(Binary,[]).
decodeList(<<>>,L) -> L;
decodeList(<<A:64/float,Rest/binary>>,L) -> decodeList(Rest,L++[A]).

