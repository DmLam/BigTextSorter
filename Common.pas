unit Common;

interface
uses Windows, SysUtils, Classes, SyncObjs;

const
  CRLF = 2573;  // #13#10

  SORT_BLOCK_SIZE = 100000;
  MERGE_BLOCK_SIZE = SORT_BLOCK_SIZE; // SORT_BLOCK_SIZE *3 div 2;
  MAX_LINE_LENGTH = 500;
  STRING_COMPARE_LENGTH = 50;

{$WARNINGS OFF}
{.$IF SORT_BLOCK_SIZE < MAX_LINE_LENGTH}
//  Incorrect constants!
{.$IFEND}
{$WARNINGS ON}

var
  Debug: boolean = false;
  TrackMemoryUsage: boolean = false;
  MaxWorkerThreadCount: integer = 1;
  MemoryAvailable: integer = 1024;
  SortBufferSize: integer = SORT_BLOCK_SIZE;
  MergeBufferSize: integer = SORT_BLOCK_SIZE;
  MergeWriteBufferSize: integer = SORT_BLOCK_SIZE;

// -1 ==> S1 < S2
// 0 ==> S1 = S2
// 1 ==> S1 > S2
function CompareStrings(const S1, S2: PAnsiChar; var S1End, S2End: PAnsiChar): integer; overload;
function CompareStrings(S1, S2: PAnsiChar): integer; overload;

procedure Log(const s: string);
function FindLastCRLF(const BufferStart, BufferEnd: PAnsiChar): PAnsiChar;
function FileSize(const FileName: string): Int64;
procedure GetConsoleCursorPos(var x, y: integer);
procedure SetConsoleCursorPos(const x, y: integer);
procedure ShowConsoleCursor(const Visible: boolean);

type
  TProgressProc = procedure(const Percent: Double);

implementation

var
  LogCS: TCriticalSection;

procedure Log(const s: string);
begin
  if Debug then
  begin
    LogCS.Acquire;
    try
      writeln(s);
    finally
      LogCS.Release;
    end;
  end;
end;

function FindLastCRLF(const BufferStart, BufferEnd: PAnsiChar): PAnsiChar;
begin
  Result := BufferEnd - 2;
  while (PWord(Result)^ <> CRLF) and (Result >= BufferStart) do
    Dec(Result);
  if Result < BufferStart then
    Result := nil;
end;

function CompareStrings(const S1, S2: PAnsiChar; var S1End, S2End: PAnsiChar): integer;
var
  CurLen: integer;
begin
  Result := 0;
  CurLen := 0;
  S1End := S1;
  S2End := S2;

  while CurLen < STRING_COMPARE_LENGTH do
  begin
    if PWord(S1End)^ = CRLF then
    begin
      if PWord(S2End)^ <> CRLF then
        Result := -1;
      Break;
    end
    else
    if PWord(S2End)^ = CRLF then
    begin
      Result := 1;
      Break;
    end
    else
    if S1End^ < S2End^ then
    begin
      Result := -1;
      Break;
    end
    else
    if S1End^ > S2End^ then
    begin
      Result := 1;
      Break;
    end
    else
    begin
      Inc(S1End);
      Inc(S2End);
    end;

    Inc(CurLen);
  end;

  // сдвинем указатели к началам соответствующих следующих строк в буферах
  while PWord(S1End)^ <> CRLF do
    Inc(S1End);
  Inc(S1End, 2);
  while PWord(S2End)^ <> CRLF do
    Inc(S2End);
  Inc(S2End, 2);
end;

function CompareStrings(S1, S2: PAnsiChar): integer;
var
  CurLen: integer;
begin
  Result := 0;
  CurLen := 0;

  while CurLen < STRING_COMPARE_LENGTH do
  begin
    if PWord(S1)^ = CRLF then
    begin
      if PWord(S2)^ <> CRLF then
        Result := -1;
      Break;
    end
    else
    if PWord(S2)^ = CRLF then
    begin
      Result := 1;
      Break;
    end
    else
    if S1^ < S2^ then
    begin
      Result := -1;
      Break;
    end
    else
    if S1^ > S2^ then
    begin
      Result := 1;
      Break;
    end
    else
    begin
      Inc(S1);
      Inc(S2);
    end;

    Inc(CurLen);
  end;
end;

function FileSize(const FileName: string): Int64;
var
  AttributeData: TWin32FileAttributeData;
begin
  if GetFileAttributesEx(PChar(FileName), GetFileExInfoStandard, @AttributeData) then 
  begin
    Int64Rec(Result).Lo := AttributeData.nFileSizeLow;
    Int64Rec(Result).Hi := AttributeData.nFileSizeHigh;
  end 
  else 
    Result := -1;
end;

procedure GetConsoleCursorPos(var x, y: integer);
var
  CBI: TConsoleScreenBufferInfo;
begin
  GetConsoleScreenBufferInfo(GetStdHandle(STD_OUTPUT_HANDLE), CBI);
  X := TCoord(CBI.dwCursorPosition).X + 1;
  Y := TCoord(CBI.dwCursorPosition).Y + 1;
end;

procedure SetConsoleCursorPos(const x, y: integer);
var
  Coord: TCoord;
begin
  Coord.X := X - 1;
  Coord.Y := Y - 1;
  SetConsoleCursorPosition(GetStdHandle(STD_OUTPUT_HANDLE), Coord);
end;

procedure ShowConsoleCursor(const Visible: boolean);
var
  CCI: TConsoleCursorInfo;
begin
  GetConsoleCursorInfo(GetStdHandle(STD_OUTPUT_HANDLE), CCI);
  CCI.bVisible := Visible;
  SetConsoleCursorInfo(GetStdHandle(STD_OUTPUT_HANDLE), CCI);
end;

initialization
  LogCS := TCriticalSection.Create;

finalization
  LogCS.Free;

end.
