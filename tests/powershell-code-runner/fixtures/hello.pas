program hello;
var
  i: integer;
  text: string;
begin
  text := 'OK:';
  for i := 1 to ParamCount do
  begin
    if i > 1 then text := text + '|';
    text := text + ParamStr(i);
  end;
  writeln(text);
  halt(3);
end.
