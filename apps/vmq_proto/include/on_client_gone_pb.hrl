%% -*- coding: utf-8 -*-
%% Automatically generated, do not edit
%% Generated by gpb_compile version 4.19.1

-ifndef(on_client_gone_pb).
-define(on_client_gone_pb, true).

-define(on_client_gone_pb_gpb_version, "4.19.1").

-ifndef('EVENTSSIDECAR.V1.ONCLIENTGONE_PB_H').
-define('EVENTSSIDECAR.V1.ONCLIENTGONE_PB_H', true).
-record('eventssidecar.v1.OnClientGone',
    % = 1, optional
    {
        timestamp = undefined :: on_client_gone_pb:'google.protobuf.Timestamp'() | undefined,
        % = 2, optional
        client_id = <<>> :: unicode:chardata() | undefined,
        % = 3, optional
        mountpoint = <<>> :: unicode:chardata() | undefined
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
