-module(spider).
-export([start/0]).

-define(BASE_PATH, "http://suigintou.desudesudesu.org/").
-define(WORKER_LIMIT, 6).
-define(SLEEP_MS, 1000).

% Retrieves a page page into a string and returns it
fetch(Url) ->
	case http:request(Url) of
		{ok, {_, _, Body}} ->
			{ok, Body};
		{error, Reason} ->
			{error, Reason}
	end.

% Takes a JSON string and returns an erlang list
parse_json(JSON) ->
	case json:decode_string(JSON) of
		{ok, Result} ->
			{ok, tuple_to_list(Result)};
		_ ->
			{error}
	end.

% Pulls JSON from a url and returns an erlang tuple
parse_json_from_url(Url) ->
	{ok, JSON} = fetch(Url),
	parse_json(JSON).

% Assumes Object is a list of {key, value} tuples, returns {key, value} where key == Key
find_key({json_object, Object}, FindKey) ->
	find_key_r(Object, FindKey).

find_key_r(Object, _FindKey) when length(Object) == 0 ->
	not_found;

find_key_r(Object, FindKey) ->
	[{Key, Value} | Tail] = Object,
	if
		Key == FindKey ->
			{Key, Value};
		Key /= FindKey ->
			find_key_r(Tail, FindKey)
	end.


% Master starts at the base page, spawns workers to download images.
start() ->
	application:start(inets),
	director(0, new_queue()).

new_queue() ->
	io:format("~nDESU~n~nFILLING NEW QUEUE YAY~n~n~n"),
	{ok, JSON} = parse_json_from_url( ?BASE_PATH ++ "/4scrape/api?a=random" ),
	JSON.

% Keeps at least ?WORKER_LIMIT amount of processes running at one time
director(Running, Queue) when length(Queue) == 0 ->
	director(Running, new_queue());

director(Running, Queue) when Running < ?WORKER_LIMIT ->
	[Image | Tail] = Queue,
	io:format("(~p/~p) Spawning worker..~n", [Running+1, ?WORKER_LIMIT]),
	spawn(fun() -> process_image(self(), Image) end),
	director(Running + 1, Tail);

director(Running, Queue) ->
	receive
		done ->
			io:format("(~p/~p) Worker completed..~n", [Running-1, ?WORKER_LIMIT]),
			timer:sleep(round(?SLEEP_MS / ?WORKER_LIMIT)),
			director(Running - 1, Queue);
		_ ->
			error
	end.

process_image(Director, Image) ->
	{_, ImageID} = find_key(Image, "img_id"),
	io:format("Processing image ~p~n", [ImageID]),

	{ok, CWD} = file:get_cwd(),
	{_, ImgPath} = find_key(Image, "img_path"),

	SourceFile = ?BASE_PATH ++ "4scrape/" ++ ImgPath,
	DestFile = CWD ++ "/img/" ++ filename:basename(ImgPath),
	io:format("Downloading ~p to ~p~n", [SourceFile, DestFile]),

	case http:request(get, {SourceFile, []}, [], [{stream, DestFile}]) of
		{ok, saved_to_file} ->
			file_saved;
		{error, _Reason} ->
			io:format("ERROR with request.");
		{stream_to_file_failed, _enoenv} ->
			io:format("ERROR: Stream to file ~p failed.~n", [DestFile]);

		_ ->
			io:format("Unknown error.")
	end,
	io:format("Processed image, sleeping for ~pms~n", [?SLEEP_MS]),
	timer:sleep(?SLEEP_MS),
	Director ! done.
