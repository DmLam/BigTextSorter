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
  TUIntArray = array[0..100] of Cardinal;  // размер такой для удобства отладки
  PUIntArray = ^TUIntArray;


type
  TPieceSorter = class(TThread)
  private
    FData, FDataEnd: PAnsiChar;
    FDataSize: integer;
    FIndexes: PUIntArray; // массив смещений строк от начала буфера. храним не в виде указателей, а в виде смещений, т.к. при необходимости
                           // скомпилировать под x64 массив с указателями будет занимать в два раза больше памяти, которая у нас ограничена
    FLengths: PUIntArray;
    FIndexesSize: integer;
    FLineCount: integer;
    FCurLineIndex: integer;
    FLastCRLFAdded: boolean; // признак того, что к последней строке был добавлен CRLF, т.к. в исходном файле его не было

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
  FLastCRLFAdded := false;
end;

destructor TPieceSorter.Destroy;
begin
  FreeMem(FLengths);
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
  I, J, P: Integer;
  Save: Cardinal;
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
        Save := FLengths[I];
        FLengths[I] := FLengths[J];
        FLengths[J] := Save;
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
  Ptr: PAnsiChar;
  L: Cardinal;
begin
  Ptr := FData + FIndexes[FCurLineIndex];
  L := FLengths[FCurLineIndex];
  Inc(FCurLineIndex);
  if (FCurLineIndex >= FLineCount) and FLastCRLFAdded then
    // после последней строки не было CRLF, поэтому удалим его и здесь
    Dec(L, 2);
  Stream.WriteBuffer(Ptr^, L);
end;

procedure TPieceSorter.Execute;
var
  IndexBlockSize: integer;
  Ptr, LineStart: PAnsiChar;
begin
  // приращение размера массива индексов выберем как среднее количество строк, помещающееся в буфер
  IndexBlockSize := FDataSize div (MAX_LINE_LENGTH div 2) * SizeOf(Integer);
  if IndexBlockSize = 0 then
    IndexBlockSize := 100;
  FIndexesSize := IndexBlockSize;
  GetMem(FIndexes, FIndexesSize);
  GetMem(FLengths, FIndexesSize);

  // подготовим массив FIndexes со смещениями каждой строки от начала буфера
  // Поскольку количество строк заранее не известно, то память под массив выделяем порциями по IndexBlockSize байт
  // Также подготавливаем аналогичный массив с длинами строк чтобы потом при записи их не искать
  FDataEnd := FData + FDataSize;
  Ptr := FData;
  FLineCount := 0;
  while Ptr < FDataEnd do
  begin
    LineStart := Ptr;
    while (Ptr < FDataEnd) and (PWord(Ptr)^ <> CRLF) do
      Inc(Ptr);

    if Ptr = FDataEnd then
    begin
      // дошли до конца буфера и там не было CRLF - добавим его и запомним этот факт, чтобы потом удалить
      // Добавлять можно, т.к. в UnitSplitter мы выделяли под буффер два лишних байта
      PWord(FDataEnd)^ := CRLF;
      FLastCRLFAdded := true;
    end;
    // сдвинем указатель на два символа CR и ДА
    Inc(Ptr, 2);

    // увеличим размер массивов индексов и длин строк если надо
    if FLineCount * SizeOf(Cardinal) >= FIndexesSize then
    begin
      Inc(FIndexesSize, IndexBlockSize);
      ReallocMem(FIndexes, FIndexesSize);
      ReallocMem(FLengths, FIndexesSize);
    end;
    FIndexes[FLineCount] := LineStart - FData;
    FLengths[FLineCount] := Ptr - LineStart;
    Inc(FLineCount);
  end;

  // Сортируем строки обычным QuickSort-ом. Реально сортируются смещения в массиве
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
    // Разобьем блок на кусочки по числу рабочих потоков. Отсортируем каждый в своем потоке и сольем, записывая сразу в файл
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
    // Последний кусок - все что осталось
    PieceSorters[MaxWorkerThreadCount - 1] := TPieceSorter.Create(PieceEnd, FData + FDataSize - PieceEnd);

    for i := 0 to MaxWorkerThreadCount - 1 do
      PieceSorters[i].Resume;

    for i := 0 to MaxWorkerThreadCount - 1 do
      PieceSorters[i].WaitFor;

    FS := nil;  // чтоб компилятор не ругался на неинициализированную переменную
    try
      FS := TWriteCachedFileStream.Create(ResultFileName, FDataSize, 0, false);
    except
      writeln('Cannot create file ', ResultFileName);

      Halt;
    end;

    // сохраняем отсортированные куски в файл, сливая их с сортировкой
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
            // кусок закончился - переместим его в конец списка и не будем больше использовать
            TempPS := PieceSorters[CurrentPiecesCount - 1];
            PieceSorters[CurrentPiecesCount - 1] := PieceSorters[MinLinePieceIndex];
            PieceSorters[MinLinePieceIndex] := TempPS;
            Dec(CurrentPiecesCount);
          end;
        end;
      end;

      // остался последний кусок в списке - запишем все его содержимое прямо в файл, т.к. больше сливать нечего
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
