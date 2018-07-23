program DataGenerator;

{$APPTYPE CONSOLE}

uses
  SysUtils, Classes;

const
  MAX_LINE_LENGTH = 500;
  DATA_FILE_SIZE = 500000;
  CRLF = #13#10;

var
  DataSize, LineLength: integer;
  CurDataSize: integer;
  s: AnsiString;
  L, i: integer;
  FS: TFileStream;
begin
  Randomize;
  CurDataSize := 0;

  if ParamCount = 0 then
  begin
    writeln('Daa size?');
    Exit;
  end;

  DataSize := StrToInt(ParamStr(1));
  LineLength := StrToIntDef(ParamStr(2), MAX_LINE_LENGTH);

  FS := TFileStream.Create('Data.txt', fmCreate);
  try
    while CurDataSize < DataSize do
    begin
      L := Random(LineLength);
      SetLength(s, L);
      for i := 1 to L do
        s[i] := Chr(Random(26) + Ord('a'));
      FS.WriteBuffer(s[1], L);
      FS.WriteBuffer(CRLF[1], Length(CRLF));
      Inc(CurDataSize, L + Length(CRLF));  
    end;
  finally
    FS.Free;
  end;
end.
