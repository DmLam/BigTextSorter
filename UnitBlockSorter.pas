unit UnitBlockSorter;

interface
uses
  SysUtils, Classes,
  Common, UnitThreadManager, UnitBufferedFileStream;

type
  TBlockSorterThread = class(TProtoThread)
  private
  type
    TIndexArray = array[0..0] of integer; 
    PIndexArray = ^TIndexArray;

  var
    FData: PAnsiChar;
    FDataSize: integer;
    FIndexes: PIndexArray; // массив смещений строк от начала буфера. храним не в виде указателей, а в виде смещений, т.к. при необходимости 
                           // скомпилировать под x64 массив с указател€ми будет занимать в два раза больше пам€ти, котора€ у нас ограничена

    procedure QuickSort(L, R: Integer);
  public
    constructor Create(const Data: PAnsiChar; const DataSize: integer; const BlockIndex: integer);

    procedure Execute; override;
  end;

implementation

procedure TBlockSorterThread.QuickSort(L, R: Integer);
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

{ TStreamSorter }

constructor TBlockSorterThread.Create(const Data: PAnsiChar; const DataSize: integer; const BlockIndex: integer);
begin
  inherited Create(BlockIndex);

  FData := Data;
  FDataSize := DataSize;
end;

procedure TBlockSorterThread.Execute;
var
  LineStart, Ptr, DataEnd: PAnsiChar;
  LineCount: integer;
  IndexesSize: integer; // текущий размер массива смещений строк
  FS: TStream;
  i: integer;
  IndexBlockSize: integer;
begin
  IndexesSize := 0;
  IndexBlockSize := MergeBufferSize div (MAX_LINE_LENGTH div 2) * SizeOf(Integer);  // приращение размера массива индексов выберем как среднее количество строк, помещающеес€ в буфер

  FIndexes := nil;
  try
    try
      // подготовим массив FIndexes со смещени€ми каждой строки от начала буфера
      // ѕоскольку количество строк заранее не известно, то пам€ть под массив выдел€ем порци€ми по INDEX_BLOCK_SIZE байт
      DataEnd := FData + FDataSize;
      Ptr := FData;
      LineCount := 0;
      while Ptr < DataEnd do
      begin
        LineStart := Ptr;
        while (Ptr < DataEnd) and (PWord(Ptr)^ <> CRLF) do
          Inc(Ptr);
        if Ptr < DataEnd then
        begin
          if LineCount * SizeOf(integer) >= IndexesSize then
          begin
            Inc(IndexesSize, IndexBlockSize);
            ReallocMem(FIndexes, IndexesSize);
          end;
          FIndexes[LineCount] := LineStart - FData;
          Inc(LineCount);

          Inc(Ptr, 2);
        end;
      end;

      // —ортируем строки обычным QuickSort-ом. –еально сортируютс€ смещени€ в массиве
      QuickSort(0, LineCount - 1);

      FS := nil;  // чтоб компил€тор не ругалс€ на неинициализированную переменную
      try
        FS := TWriteCachedFileStream.Create(ResultFileName, FDataSize, 0, false);
      except
        writeln('Cannot create file ', ResultFileName);

        Halt;
      end;

      // сохран€ем отсортированные строки в файл
      try
        for i := 0 to LineCount - 1 do
        begin
          Ptr := FData + FIndexes[i];
          LineStart := Ptr;
          while (Ptr < DataEnd) and (PWord(Ptr)^ <> CRLF) do
            Inc(Ptr);
          if Ptr < DataEnd then
            Inc(Ptr, 2);  // CRLF
          FS.WriteBuffer(LineStart^, Ptr - LineStart);
        end;
      finally
        FS.Free;
      end;
    finally
      FreeMem(FData);
    end;
  finally
    FreeMem(FIndexes);
  end;

  inherited;
end;

end.
