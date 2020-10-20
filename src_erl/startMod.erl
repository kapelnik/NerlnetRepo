%%%-------------------------------------------------------------------
%%% @author ziv
%%% @copyright (C) 2020, <COMPANY>
%%% @doc
%%%
%%% @end
%%% Created : 20. Oct 2020 21:56
%%%-------------------------------------------------------------------
-module(startMod).
-author("ziv").

%% API
-export([start/0, startFSM/4]).


start()->
  io:fwrite("start module_create ~n"),
  _Pid1 = spawn(fun()->startFSM(0.01,[1,2,3,2,3,2,1,0,1,2,3,2,3,2,1,0,1,2,3,2,3,2,1,0,1,2,3,2,3,2,1,0,0,1,0,1,0,1,0,1],
    [1,2,3,2,3,2,1,0,1,2,3,2,3,2,1,0,1,2,3,2,3,2,1,0,1,2,3,2,3,2,1,0],0) end),
  timer:sleep(500),
  _Pid2 = spawn(fun()->startFSM(0.01,[1,2,3,2,3,2,1,0,1,2,3,2,3,2,1,0,1,2,3,2,3,2,1,0,1,2,3,2,3,2,1,0,0,1,0,1,0,1,0,1],
    [1,2,3,2,3,2,1,0,1,2,3,2,3,2,1,0,1,2,3,2,3,2,1,0,1,2,3,2,3,2,1,0],1) end).

startFSM(LearningRate, Data_Label, Data, Mid)->
  nerlNetStatem:start_link(),
  nerlNetStatem:create(Mid,LearningRate),
  timer:sleep(500),
  nerlNetStatem:train(Mid,Data_Label),
  timer:sleep(500),
  nerlNetStatem:predict(Mid,Data).
