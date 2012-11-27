-module(sql2erl).

-compile(export_all).

test1() ->
    Str = "select * from abc where a=b and (c=d or d=f) and (d =i or a=u)",
    %Str = "select * from abc where a=1",
    {ErlExpr, SymbolTable} = parse(Str),
    F = erl({ErlExpr, SymbolTable}),
    io:format(user, "F() ~p~n", [F()]).

parse(Sql) ->
    Str = string:strip(Sql),
    NewSql = case [lists:nth(length(Str), Str)] of
        ";" -> Str;
        _ -> Str ++ ";"
    end,
    {ok, SqlTokens, _} = sql_lex:string(NewSql),
    {ok, [ParseTree|_]} = sql_parse:parse(SqlTokens),
    walk(ParseTree).

walk({select, [_Hints, _Opt, _Fields, _Into, _From, {where, Where}, _GroupBy, _Having, _OrderBy]}) ->
    {ErlExpr, SymbolTable, _} = walk_where(Where, [], 0),
    {ErlExpr, SymbolTable}.
    
walk_where({Op, L, R}, Symb, VarNum) when is_tuple(L), is_tuple(R), is_atom(Op) ->    
    {ExprnLeft, NewSymb, NewVarNum} = walk_where(L, Symb, VarNum), % walking left subtree
    {ExprnRight, NewSymb1, NewVarNum1} = walk_where(R, NewSymb, NewVarNum), % walking right subtree
    case Op of
    'and' -> {"(" ++ ExprnLeft ++ ") andalso (" ++ ExprnRight ++ ")", NewSymb1, NewVarNum1};
    'or' -> {"(" ++ ExprnLeft ++ ") orelse (" ++ ExprnRight ++ ")", NewSymb1, NewVarNum1}
    end;
walk_where({'=', L, R}, Symb, VarNum) when is_binary(L), is_binary(R) ->
    VarLeft = "Var"++integer_to_list(VarNum),
    VarRight = "Var"++integer_to_list(VarNum+1),
    {VarLeft++" == "++VarRight,
    [{list_to_atom(VarLeft), L, 1},{list_to_atom(VarRight), R, 2}|Symb],
    VarNum+2}.

erl({Str, SymbolTable}) ->
    String = "fun() ->\n"
    ++
    Str
    ++"\nend.",

    io:format(user, "Fun "++String++"~nBindings ~p~n", [SymbolTable]),
    {ok,ErlTokens,_}=erl_scan:string(String),
    {ok,ErlAbsForm}=erl_parse:parse_exprs(ErlTokens),
    Bindings=bind(SymbolTable, erl_eval:new_bindings()),
    {value,Fun,_}=erl_eval:exprs(ErlAbsForm,Bindings),
    Fun.

bind([], Binds) -> Binds;
bind([{Var,_,Val}|ST], Binds) ->
    NewBinds=erl_eval:add_binding(Var,Val,Binds),
    bind(ST, NewBinds).
