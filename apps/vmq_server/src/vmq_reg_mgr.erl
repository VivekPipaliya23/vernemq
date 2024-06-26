%% Copyright 2018 Erlio GmbH Basel Switzerland (http://erl.io)
%%
%% Licensed under the Apache License, Version 2.0 (the "License");
%% you may not use this file except in compliance with the License.
%% You may obtain a copy of the License at
%%
%%     http://www.apache.org/licenses/LICENSE-2.0
%%
%% Unless required by applicable law or agreed to in writing, software
%% distributed under the License is distributed on an "AS IS" BASIS,
%% WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
%% See the License for the specific language governing permissions and
%% limitations under the License.

-module(vmq_reg_mgr).

-include("vmq_server.hrl").

-behaviour(gen_server).
%% API functions
-export([
    start_link/0,
    all_queues_setup_status/0,
    handle_new_sub_event/2
]).

%% gen_server callbacks
-export([
    init/1,
    handle_call/3,
    handle_cast/2,
    handle_info/2,
    terminate/2,
    code_change/3
]).

-record(state, {
    status = init,
    event_handler,
    event_queue = queue:new()
}).

%%%===================================================================
%%% API functions
%%%===================================================================

%%--------------------------------------------------------------------
%% @doc
%% Starts the server
%%
%% @spec start_link() -> {ok, Pid} | ignore | {error, Error}
%% @end
%%--------------------------------------------------------------------
start_link() ->
    gen_server:start_link({local, ?MODULE}, ?MODULE, [], []).

-spec all_queues_setup_status() -> term().
all_queues_setup_status() ->
    gen_server:call(?MODULE, status).

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
init([]) ->
    load_redis_functions(),

    Self = self(),
    spawn_link(
        fun() ->
            vmq_reg:fold_subscribers(fun setup_queue/3, ignore),
            Self ! all_queues_setup
        end
    ),
    EventHandler = vmq_reg:subscribe_subscriber_changes(),
    {ok, #state{event_handler = EventHandler}}.

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
handle_call(status, _From, #state{status = Status} = State) ->
    Reply = Status,
    {reply, Reply, State};
handle_call(_Request, _From, State) ->
    Reply = ok,
    {reply, Reply, State}.

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
handle_info(
    all_queues_setup,
    #state{
        event_handler = Handler,
        event_queue = Q
    } = State
) ->
    lists:foreach(
        fun(Event) ->
            handle_event(Handler, Event)
        end,
        queue:to_list(Q)
    ),
    {noreply, State#state{status = ready, event_queue = undefined}};
handle_info(Event, #state{status = init, event_queue = Q} = State) ->
    {noreply, State#state{event_queue = queue:in(Event, Q)}};
handle_info(Event, #state{event_handler = Handler} = State) ->
    handle_event(Handler, Event),
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
setup_queue(SubscriberId, Subs, Acc) ->
    case lists:keyfind(node(), 1, Subs) of
        {_Node, false, _Subs} ->
            vmq_queue_sup_sup:start_queue(SubscriberId, false);
        _ ->
            Acc
    end.

handle_event(Handler, Event) ->
    case Handler(Event) of
        {delete, _SubscriberId, _} ->
            %% TODO: we might consider a queue cleanup here.
            ignore;
        {update, _SubscriberId, [], []} ->
            %% noop
            ignore;
        {update, SubscriberId, _OldSubs, NewSubs} ->
            handle_new_sub_event(SubscriberId, NewSubs);
        ignore ->
            ignore
    end.

handle_new_sub_event(SubscriberId, Subs) ->
    Sessions = vmq_subscriber:get_sessions(Subs),
    case lists:keymember(node(), 1, Sessions) of
        true ->
            %% The local queue will have been started directly via
            %% `vmq_reg:register_subscriber` in the fsm.
            ignore;
        false ->
            %% we may migrate an existing queue to a remote queue
            %% Do we have a local queue to migrate?
            case vmq_queue_sup_sup:get_queue_pid(SubscriberId) of
                not_found ->
                    ignore;
                QPid ->
                    case is_allow_multi(QPid) of
                        true ->
                            %% no need to migrate if we allow multiple sessions
                            ignore;
                        false ->
                            handle_new_remote_subscriber(SubscriberId, QPid, Sessions);
                        error ->
                            ignore
                    end
            end
    end.

%% Local queue found, only terminate this queue if
%% 1. NewQueue.clean_session = false AND
%% 2. OldQueue.allow_multiple_sessions = false AND
%% 3. Only one concurrent Session exist
%% if OldQueue.clean_session = true, queue migration is
%% aborted by the OldQueue process.
handle_new_remote_subscriber(SubscriberId, QPid, [{_NewNode, false}] = _Session) ->
    % Case 1. AND 3.
    terminate_queue(SubscriberId, ?REMOTE_SESSION_TAKEN_OVER, QPid);
handle_new_remote_subscriber(SubscriberId, QPid, [{_NewNode, true} = _Session]) ->
    %% New remote queue uses clean_session=true, we have to wipe this local session
    cleanup_queue(SubscriberId, ?REMOTE_SESSION_TAKEN_OVER, QPid).

terminate_queue(SubscriberId, Reason, QPid) ->
    vmq_reg_sync:sync(
        {cleanup, SubscriberId},
        fun() ->
            vmq_queue:terminate(QPid, Reason)
        end,
        node(),
        60000
    ).

cleanup_queue(SubscriberId, Reason, QPid) ->
    vmq_reg_sync:sync(
        {cleanup, SubscriberId},
        fun() ->
            vmq_queue:cleanup(QPid, Reason)
        end,
        node(),
        60000
    ).

is_allow_multi(QPid) ->
    case vmq_queue:get_opts(QPid) of
        #{allow_multiple_sessions := AllowMulti} -> AllowMulti;
        {error, _} -> error
    end.

load_redis_functions() ->
    LuaDir = application:get_env(vmq_server, redis_lua_dir, "./etc/lua"),
    {ok, RemapSubscriberScript} = file:read_file(LuaDir ++ "/remap_subscriber.lua"),
    {ok, SubscribeScript} = file:read_file(LuaDir ++ "/subscribe.lua"),
    {ok, UnsubscribeScript} = file:read_file(LuaDir ++ "/unsubscribe.lua"),
    {ok, DeleteSubscriberScript} = file:read_file(LuaDir ++ "/delete_subscriber.lua"),
    {ok, FetchMatchedTopicSubscribersScript} = file:read_file(
        LuaDir ++ "/fetch_matched_topic_subscribers.lua"
    ),
    {ok, FetchSubscriberScript} = file:read_file(LuaDir ++ "/fetch_subscriber.lua"),
    {ok, GetLiveNodesScript} = file:read_file(LuaDir ++ "/get_live_nodes.lua"),
    {ok, MigrateOfflineQueueScript} = file:read_file(LuaDir ++ "/migrate_offline_queue.lua"),
    {ok, ReapSubscribersScript} = file:read_file(LuaDir ++ "/reap_subscribers.lua"),

    {ok, <<"remap_subscriber">>} = vmq_redis:query(
        vmq_redis_client,
        [?FUNCTION, "LOAD", "REPLACE", RemapSubscriberScript],
        ?FUNCTION_LOAD,
        ?REMAP_SUBSCRIBER
    ),
    {ok, <<"subscribe">>} = vmq_redis:query(
        vmq_redis_client,
        [?FUNCTION, "LOAD", "REPLACE", SubscribeScript],
        ?FUNCTION_LOAD,
        ?SUBSCRIBE
    ),
    {ok, <<"unsubscribe">>} = vmq_redis:query(
        vmq_redis_client,
        [?FUNCTION, "LOAD", "REPLACE", UnsubscribeScript],
        ?FUNCTION_LOAD,
        ?UNSUBSCRIBE
    ),
    {ok, <<"delete_subscriber">>} = vmq_redis:query(
        vmq_redis_client,
        [?FUNCTION, "LOAD", "REPLACE", DeleteSubscriberScript],
        ?FUNCTION_LOAD,
        ?DELETE_SUBSCRIBER
    ),
    {ok, <<"fetch_matched_topic_subscribers">>} = vmq_redis:query(
        vmq_redis_client,
        [?FUNCTION, "LOAD", "REPLACE", FetchMatchedTopicSubscribersScript],
        ?FUNCTION_LOAD,
        ?FETCH_MATCHED_TOPIC_SUBSCRIBERS
    ),
    {ok, <<"fetch_subscriber">>} = vmq_redis:query(
        vmq_redis_client,
        [?FUNCTION, "LOAD", "REPLACE", FetchSubscriberScript],
        ?FUNCTION_LOAD,
        ?FETCH_SUBSCRIBER
    ),
    {ok, <<"get_live_nodes">>} = vmq_redis:query(
        vmq_redis_client,
        [?FUNCTION, "LOAD", "REPLACE", GetLiveNodesScript],
        ?FUNCTION_LOAD,
        ?GET_LIVE_NODES
    ),
    {ok, <<"migrate_offline_queue">>} = vmq_redis:query(
        vmq_redis_client,
        [?FUNCTION, "LOAD", "REPLACE", MigrateOfflineQueueScript],
        ?FUNCTION_LOAD,
        ?MIGRATE_OFFLINE_QUEUE
    ),
    {ok, <<"reap_subscribers">>} = vmq_redis:query(
        vmq_redis_client,
        [?FUNCTION, "LOAD", "REPLACE", ReapSubscribersScript],
        ?FUNCTION_LOAD,
        ?REAP_SUBSCRIBERS
    ).
