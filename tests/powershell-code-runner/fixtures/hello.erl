main(Values) ->
    io:format("OK:~s~n", [string:join(Values, "|")]),
    halt(3).
