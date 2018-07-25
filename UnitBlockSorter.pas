unit UnitBlockSorter;

interface
uses
  SysUtils, Classes,
  Common, UnitWorker, UnitBufferedFileStream;

type
  TBlockSorter = class(TWorker)
  private
    FData: PAnsiChar;
    FDataSize: integer;

  public
    constructor Create(const Data: PAnsiChar; const DataSize: integer; const BlockIndex: integer);

    procedure Execute; override;
  end;

implementation

type
  TIndexArray = array[0..0] of integer;
  PIndexArray = ^TIndexArray;


type
  TPieceSorter = class(TThread)
  private
    FData, FDataEnd: PAnsiChar;
    FDataSize: integer;
    FIndexes: PIndexArray; // массив смещений строк от начала буфера. храним не в виде указателей, а в виде смещений, т.к. при необходимости
                           // скомпилировать под x64 массив с указател€ми будет занимать в два раза больше пам€ти, котора€ у нас ограничена
    FIndexesSize: integer;
    FLineCount: integer;
    FCurLineIndex: integer;

    procedure QuickSort(L, R: Integer);
    function GetCurLine: PAnsiChar;

  public
    constructor Create(const Data: PAnsiChar; const DataSize: integer);
    destructor Destroy; override;

    procedure Execute; override;
    procedure SaveCurLine(const Stream: TStream);

    property LineCount: integer
      read FLineCount;
    property CurLine: PAnsiChar
      read GetCurLine;   
    property CurLineIndex: integer
      read FCurLineIndex;
  end;

{ TBlockSorter }

constructor TPieceSorter.Create(const Data: PAnsiChar; const DataSize: integer);
begin
  inherited Create(true);  // create suspended

  FData := Data;
  FDataSize := DataSize;
  FCurLineIndex := 0;
end;

destructor TPieceSorter.Destroy;
begin
  FreeMem(FIndexes);

  inherited;
end;

function TPieceSorter.GetCurLine: PAnsiChar;
begin
  Result := nil;

  if (FCurLineIndex >= 0) and (FCurLineIndex < FLineCount) then
    Result := FData + FIndexes[FCurLineIndex];
end;

procedure TPieceSorter.QuickSort(L, R: Integer);
var
  I, J, P, Save: Integer;
begin
  repeat
    I := L;
    J := R;
    P := (L + R) shr 1;
    repeat
      while CompareStrings(FData + FIndexes[I], FData + FIndexes[P]) < 0 do
        Inc(I);
      while CompareStrings(FData + FIndexes[J], FData + FIndexes[P]) > 0 do
        Dec(J);
      if I <= J then
      begin
        Save := FIndexes[I];
        FIndexes[I] := FIndexes[J];
        FIndexes[J] := Save;
        if P = I then
          P := J
        else
        if P = J then
          P := I;
        Inc(I);
        Dec(J);
      end;
    until I > J;
    if L < J then QuickSort(L, J);
    L := I;
  until I >= R;
end;

procedure TPieceSorter.SaveCurLine(const Stream: TStream);
var
  Ptr, LineStart: PAnsiChar;
begin
  Ptr := FData + FIndexes[FCurLineIndex];
  LineStart := Ptr;
  while (Ptr < FDataEnd) and (PWord(Ptr)^ <> CRLF) do
    Inc(Ptr);
  if Ptr < FDataEnd then
    Inc(Ptr, 2);  // CRLF
  Stream.WriteBuffer(LineStart^, Ptr - LineStart);
  Inc(FCurLineIndex);
end;

procedure TPieceSorter.Execute;
var
  IndexBlockSize: integer;
  Ptr, LineStart: PAnsiChar;
begin
  // приращение размера массива индексов выберем как среднее количество строк, помещающеес€ в буфер
  IndexBlockSize := FDataSize div (MAX_LINE_LENGTH div 2) * SizeOf(Integer);
  if IndexBlockSize = 0 then
    IndexBlockSize := 100;
  FIndexesSize := IndexBlockSize;
  GetMem(FIndexes, FIndexesSize);

  // подготовим массив FIndexes со смещени€ми каждой строки от начала буфера
  // ѕоскольку количество строк заранее не известно, то пам€ть под массив выдел€ем порци€ми по IndexBlockSize байт
  // ћожно еще немного ускорить дальнейшийпроцесс сохранени€ строк в файл если на этом этапе хранить не только
  // начала строк, но и их размеры
  FDataEnd := FData + FDataSize;
  Ptr := FData;
  FLineCount := 0;
  while Ptr < FDataEnd do
  begin
    LineStart := Ptr;
    while (Ptr < FDataEnd) and (PWord(Ptr)^ <> CRLF) do
      Inc(Ptr);
    if Ptr < FDataEnd then
    begin
      if FLineCount * SizeOf(integer) >= FIndexesSize then
      begin
        Inc(FIndexesSize, IndexBlockSize);
        ReallocMem(FIndexes, FIndexesSize);
      end;
      FIndexes[FLineCount] := LineStart - FData;
      Inc(FLineCount);

      Inc(Ptr, 2);
    end;
  end;

  // —ортируем строки обычным QuickSort-ом. –еально сортируютс€ смещени€ в массиве
  QuickSort(0, FLineCount - 1);
end;

constructor TBlockSorter.Create(const Data: PAnsiChar; const DataSize: integer; const BlockIndex: integer);
begin
  inherited Create(BlockIndex);

  FData := Data;
  FDataSize := DataSize;
end;

procedure TBlockSorter.Execute;
var
  PieceSorters: array of TPieceSorter;
  PieceSize: integer;
  PiecePtr, PieceEnd: PAnsiChar;
  FS: TStream;
  i: integer;
  MinLinePieceIndex: Integer;
  CurrentPiecesCount: integer;
  TempPS: TPieceSorter;
begin
  try
    // –азобьем блок на кусочки по числу рабочих потоков. ќтсортируем каждый в своем потоке и сольем, записыва€ сразу в файл
    PieceSize := FDataSize div MaxWorkerThreadCount;
    PiecePtr := FData;
    PieceEnd := PiecePtr;
    SetLength(PieceSorters, MaxWorkerThreadCount);
    for i := 0 to MaxWorkerThreadCount  - 2 do
    begin
      PieceEnd := FindLastCRLF(PiecePtr, PiecePtr + PieceSize);
      if PieceEnd = nil then
      begin
        writeln('Line too long');
        Halt;
      end
      else
        Inc(PieceEnd, 2); // CRLF
      PieceSorters[i] := TPieceSorter.Create(PiecePtr, PieceEnd - PiecePtr);
      PiecePtr := PieceEnd;
    end;
    // ѕоследний кусок - все что осталось
    PieceSorters[MaxWorkerThreadCount - 1] := TPieceSorter.Create(PieceEnd, FData + FDataSize - PieceEnd);

    for i := 0 to MaxWorkerThreadCount - 1 do
      PieceSorters[i].Resume;

    for i := 0 to MaxWorkerThreadCount - 1 do
      PieceSorters[i].WaitFor;

    FS := nil;  // чтоб компил€тор не ругалс€ на неинициализированную переменную
    try
      FS := TWriteCachedFileStream.Create(ResultFileName, FDataSize, 0, false);
    except
      writeln('Cannot create file ', ResultFileName);

      Halt;
    end;

    // сохран€ем отсортированные куски в файл, слива€ их с сортировкой
    try
      CurrentPiecesCount := MaxWorkerThreadCount;  // количество непустых еще кусков
      while CurrentPiecesCount > 1 do
      begin
        // выбираем кусок у с минимальной строкой
        MinLinePieceIndex := -1;
        for i := 0 to CurrentPiecesCount - 1 do
        begin
          if MinLinePieceIndex = -1 then
            MinLinePieceIndex := i
          else
            if CompareStrings(PieceSorters[MinLinePieceIndex].CurLine, PieceSorters[i].CurLine) > 0  then
              MinLinePieceIndex := i;
        end;

        if MinLinePieceIndex <> -1 then
        begin
          PieceSorters[MinLinePieceIndex].SaveCurLine(FS);
          if PieceSorters[MinLinePieceIndex].CurLine = nil then
          begin
            // кусок закончилс€ - переместим его в конец списка и не будем больше использовать
            TempPS := PieceSorters[CurrentPiecesCount - 1];
            PieceSorters[CurrentPiecesCount - 1] := PieceSorters[MinLinePieceIndex];
            PieceSorters[MinLinePieceIndex] := TempPS;
            Dec(CurrentPiecesCount);
          end;
        end;
      end;

      // осталс€ последний кусок в списке - запишем все его содержимое пр€мо в файл, т.к. больше сливать нечего
      while PieceSorters[0].CurLine <> nil do
        PieceSorters[0].SaveCurLine(FS);

      for i := 0 to MaxWorkerThreadCount - 1 do
        PieceSorters[i].Free;

    finally
      FS.Free;
    end;
  finally
    FreeMem(FData);
  end;

  inherited;
end;

end.
