%% @doc Testcases handler.
-module(testcases_handler).

-export([init/2]).
-export([allowed_methods/2]).
-export([content_types_provided/2]).
-export([content_types_accepted/2]).
-export([charsets_accepted/2]).

-export([from_json/2]).
-include("message_templates.hrl").

%-define(TEST,1).
-ifdef(TEST).
-define(DBG(Message),io:format("Module: ~p, Line:~p, :~p~n",[?MODULE ,?LINE, Message])).
-else.
-define(DBG(Message),true).
-endif.

init(Req, Opts) ->
    _Headers = cowboy_req:headers(Req),
    %%_Headers = cowboy_req:meta(media_type,Req),
    ?DBG([[_Headers]]),
    {cowboy_rest, Req, Opts}.

allowed_methods(Req, State) ->
    {[<<"GET">>, <<"POST">>], Req, State}.

charsets_accepted(Req, State) ->
    {[<<"utf-8">>,<<"UTF-8">>], Req, State}.

content_types_provided(Req, State) ->
    {[
      {<<"application/json">>, list_to_json}
     ], Req, State}.

content_types_accepted(Req, State) ->
    {[
      {{<<"application">>, <<"json">>, [{<<"charset">>, <<"utf-8">>}]},from_json}
     ], Req, State}.

from_json(Req, State) ->
    ?DBG(["from json"]),
    try cowboy_req:method(Req) of
	<<"POST">> ->
	    ?DBG(["POST received"]), 
	    ?DBG(["Request testcases"]),
	    {ok,ReqBody,Req2} = cowboy_req:body(Req),
	    [{<<"data">>,SelectedSuites}] = jsx:decode(ReqBody),	
	    ?DBG(SelectedSuites),
	    ListOfSuitesPathes = selected_suites_to_path_list(SelectedSuites),
	    ListOfTcRecords = testcase_db_update(ListOfSuitesPathes),
	    ?DBG(ets:tab2list(jtc_tc_db)),
	    PreJsonList = tc_records_to_jsx(ListOfTcRecords),
	    ?DBG(PreJsonList),
	    TcJson = jsx:encode(PreJsonList),
	    ?DBG(TcJson),
	    Response = <<"{\"data\" : ",TcJson/bitstring,"}">>,
	    ?DBG(Response),	
	    {true,cowboy_req:set_resp_body(Response,Req2),State};
	_ ->
	    {true, Req, State}
    catch
	ErrorClass:Error -> 
	    error_logger:error_msg(
	      "Error in POST testcases processing ~p: ~p ~n", [ErrorClass,Error]),
	     {true, Req, State}
    end.


testcase_db_update(SelectedSuites) ->
  testcase_db_update(SelectedSuites, []).

testcase_db_update([H|SelectedSuites], Acc) ->
    StringPath = bitstring_to_list(H),
    UpdTime = filelib:last_modified(StringPath),
    ?DBG(UpdTime),
    [SuiteRecord] = ets:lookup(jtc_suites_db, H),
    UpdatedRecords = 
	case ets:take(jtc_tc_db, H)  of
	    [] -> 
		error_logger:info_msg(
		  "No info about ~p: compiling~n", [H]),
		compile_suite(StringPath);
	    List -> 
		case UpdTime == SuiteRecord#suites.update_time of
		    true -> List;
		    false -> 
			error_logger:info_msg(
			  "File ~p updated: recompiling~n", [H]),
			CS = compile_suite(StringPath),
			ets:insert(jtc_suites_db,SuiteRecord#suites{update_time = UpdTime}),
			CS
		end
	end,
    testcase_db_update(SelectedSuites, lists:append(UpdatedRecords,Acc));    
testcase_db_update([],Acc) ->
    ets:insert(jtc_tc_db,Acc),
    Acc.

tc_records_to_jsx(ListOfPathTcTuples) ->
    tc_records_to_jsx(ListOfPathTcTuples, []).

tc_records_to_jsx([#testcase{path=Path,id = Tc, active = Active}|ListOfPathTcTuples], Acc) 
  when is_atom(Tc) ->
    JsxList = 
	[{<<"path">>,Path},
	 {<<"tc">>, atom_to_binary(Tc,utf8)},
	 {<<"active">>,Active}],
    tc_records_to_jsx(ListOfPathTcTuples, [JsxList|Acc]);
tc_records_to_jsx([], Acc) ->
    Acc;
tc_records_to_jsx([Data|ListOfPathTcTuples], Acc) ->
    error_logger:warning_msg("Not test description structure matched ~p~n", [Data]),
    tc_records_to_jsx(ListOfPathTcTuples, Acc).


selected_suites_to_path_list(JsonListSelectedSuites)->
    selected_suites_to_path_list(JsonListSelectedSuites,[]).

selected_suites_to_path_list([H|JsonListSelectedSuites], Acc)->
    BinaryEncodedPath = proplists:get_value(<<"path">>,H),
    selected_suites_to_path_list(JsonListSelectedSuites, [BinaryEncodedPath|Acc]);
selected_suites_to_path_list([],Acc)->
    Acc.

compile_suite(Path)->
    BaseName = filename:rootname(filename:basename(Path)),
    BeamDir = application:get_env(web_server,tmp_dir,[]),	
    code:purge(list_to_atom(BaseName)),
    compile:file(Path,[{outdir,BeamDir}]),
    code:load_abs(filename:join(BeamDir,BaseName)),
    Module = list_to_atom(BaseName),
    PathBitstring = list_to_bitstring(Path),
    TcRecords = [#testcase{id=Tc,path=PathBitstring, active=false} || Tc <- Module:all()],
    TcRecords.

















