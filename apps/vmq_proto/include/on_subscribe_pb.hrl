%% -*- coding: utf-8 -*-
%% Automatically generated, do not edit
%% Generated by gpb_compile version 4.19.1

-ifndef(on_subscribe_pb).
-define(on_subscribe_pb, true).

-define(on_subscribe_pb_gpb_version, "4.19.1").

-ifndef('EVENTSSIDECAR.V1.ONSUBSCRIBE_PB_H').
-define('EVENTSSIDECAR.V1.ONSUBSCRIBE_PB_H', true).
-record('eventssidecar.v1.OnSubscribe',
    % = 1, optional
    {
        timestamp = undefined :: on_subscribe_pb:'google.protobuf.Timestamp'() | undefined,
        % = 2, optional
        client_id = <<>> :: unicode:chardata() | undefined,
        % = 3, optional
        mountpoint = <<>> :: unicode:chardata() | undefined,
        % = 4, optional
        username = <<>> :: unicode:chardata() | undefined,
        % = 5, repeated
        topics = [] :: [on_subscribe_pb:'eventssidecar.v1.TopicInfo'()] | undefined
    }
).
-endif.

-ifndef('EVENTSSIDECAR.V1.TOPICINFO_PB_H').
-define('EVENTSSIDECAR.V1.TOPICINFO_PB_H', true).
-record('eventssidecar.v1.TopicInfo',
    % = 1, optional
    {
        topic = <<>> :: unicode:chardata() | undefined,
        % = 2, optional, 32 bits
        qos = 0 :: integer() | undefined
    }
).
-endif.

-ifndef('GOOGLE.PROTOBUF.TIMESTAMP_PB_H').
-define('GOOGLE.PROTOBUF.TIMESTAMP_PB_H', true).
-record('google.protobuf.Timestamp',
    % = 1, optional, 64 bits
    {
        seconds = 0 :: integer() | undefined,
        % = 2, optional, 32 bits
        nanos = 0 :: integer() | undefined
    }
).
-endif.

-endif.
