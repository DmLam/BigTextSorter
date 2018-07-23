unit UnitBlockMerger;

interface
uses
  Windows, SysUtils, Classes,
  Common, UnitThreadManager;

type
  TBlockMergerThread = class(TProtoThread)
  private
    FFileName1, FFileName2: string;
    type
      TBuffer = record
      private
        FFileName: string;
        FBuffer: PAnsiChar;
        FCurPtr: PAnsiChar;
        FBufferEnd: PAnsiChar;  // указатель на конец последней полной строки в буффере (точнее, начало следующей - не до конца поместившейся
        FStream: TStream;
        BytesInBuffer: integer;

        procedure SetCurPtr(const Value: PAnsiChar);
        procedure ReadBlockFromFile;
      public
        constructor Create(const FileName: string);
        procedure Destroy;

        function IsEmpty: boolean;
        procedure CopyTo(const Destination: TStream);
        procedure CheckPtr(var Ptr: PAnsiChar); // проверяет, что указатель не вышел за границу буфера - на случай добавленного в конце последней строки CRLF

        property CurPtr: PAnsiChar
          read FCurPtr write SetCurPtr;
      end;
  public
    constructor Create(const BlockIndex: integer; const FileName1, FileName2, ResultFileName: string);

    procedure Execute; override;
  end;

implementation

uses UnitBufferedFileStream;

{ TBlockMerger.TBuffer }

procedure TBlockMergerThread.TBuffer.CheckPtr(var Ptr: PAnsiChar);
begin
  if Ptr > FBufferEnd then
    Ptr := FBufferEnd;
end;

procedure TBlockMergerThread.TBuffer.CopyTo(const Destination: TStream);
begin
  // записываем остаток буфера и остаток файла в поток назначения
  Destination.WriteBuffer(FCurPtr^, FBuffer + BytesInBuffer - FCurPtr);
  if FStream.Size <> FStream.Position then
    Destination.CopyFrom(FStream, FStream.Size - FStream.Position);
  // установим признаки пустоты потока
  FBufferEnd := FBuffer;
  FCurPtr := FBuffer;
end;

constructor TBlockMergerThread.TBuffer.Create(const FileName: string);
begin
  FFileName := FileName;
  try
    FStream := TFileStream.Create(FileName, fmOpenRead);
  except
    writeln('Cannot open temporary file ', FileName);

    Halt;
  end;
  GetMem(FBuffer, MergeBufferSize + 2);  // 2 байта для CRLF, которого может не быть после последней строки в файле
  BytesInBuffer := 0;
  ReadBlockFromFile;
end;

procedure TBlockMergerThread.TBuffer.Destroy;
begin
  FreeMem(FBuffer);
  FStream.Free;

  if not Debug then
    DeleteFile(FFileName);
end;

function TBlockMergerThread.TBuffer.IsEmpty: boolean;
begin
  Result := (FCurPtr >= FBufferEnd) and (FStream.Position = FStream.Size);
end;

procedure TBlockMergerThread.TBuffer.ReadBlockFromFile;
var
  BufRestSize: integer;
  BufStart: PAnsiChar;
begin
  if BytesInBuffer > 0 then
  begin
    BufRestSize := FBuffer + BytesInBuffer - FBufferEnd;  // количество символов от строки, не поместившейся в буфер целиком от предыдущего чтения
    if BufRestSize > 0 then
    begin
      // перенесем в начало буфера этот непоместившийся в прошлый раз кусок строки
      BufStart := FBuffer + BufRestSize;
      Move(FBufferEnd^, FBuffer^, BufRestSize);
    end
    else
      BufStart := FBuffer;
  end
  else
  begin
    BufRestSize := 0;
    BufStart := FBuffer;
  end;
  FCurPtr := FBuffer;

  if FStream.Position <> FStream.Size then
  begin
    BytesInBuffer := FStream.Read(BufStart^, MergeBufferSize - BufRestSize) + BufRestSize;
    FBufferEnd := FindLastCRLF(BufStart, FBuffer + BytesInBuffer);
    if FBufferEnd = nil then
    begin
      // прочитана последняя строка в файле, поместившаяся целиком в буфер и после нее не было CRLF
      FBufferEnd := FBuffer + BytesInBuffer;
      if (BytesInBuffer < 2) or (PWord(FBufferEnd - 2)^ <> CRLF) then
        PWord(FBufferEnd)^ := CRLF;
    end
    else
      Inc(FBufferEnd, 2)
  end
  else
    FBufferEnd := FBuffer + BufRestSize;
end;

procedure TBlockMergerThread.TBuffer.SetCurPtr(const Value: PAnsiChar);
begin
  if Value >= FBufferEnd then
    ReadBlockFromFile
  else
    FCurPtr := Value;
end;

{ TBlockMerger }

constructor TBlockMergerThread.Create(const BlockIndex: integer; const FileName1, FileName2, ResultFileName: string);
begin
  inherited Create(BlockIndex);

  FFileName1 := FileName1;
  FFileName2 := FileName2;
end;

procedure TBlockMergerThread.Execute;
var
  RF: TStream;
  Buffer1, Buffer2: TBuffer;
  NextStr1, NextStr2: PAnsiChar;
begin
  Buffer1.Create(FFileName1);
  try
    Buffer2.Create(FFileName2);
    try
      RF := TWriteCachedFileStream.Create(ResultFileName, MergeWriteBufferSize, 0, false);
      try
        while not Buffer1.IsEmpty and not Buffer2.IsEmpty do
        begin
          if CompareStrings(Buffer1.CurPtr, Buffer2.CurPtr, NextStr1, NextStr2) <= 0 then
          begin
            Buffer1.CheckPtr(NextStr1);
            RF.WriteBuffer(Buffer1.CurPtr^, NextStr1 - Buffer1.CurPtr);
            Buffer1.CurPtr := NextStr1;
          end
          else
          begin
            Buffer2.CheckPtr(NextStr2);
            RF.WriteBuffer(Buffer2.CurPtr^, NextStr2 - Buffer2.CurPtr);
            Buffer2.CurPtr := NextStr2;
          end;
        end;
        // дописать остатки второго потока
        if Buffer1.IsEmpty then
          Buffer2.CopyTo(RF)
        else
          Buffer1.CopyTo(RF);
      finally
        RF.Free;
      end;
    finally
      try
        Buffer2.Destroy;
      except
        NextStr1 := nil;
      end;
    end;
  finally
    Buffer1.Destroy;
  end;

  Log(Format('Merged %s + %s -> %s', [FFileName1, FFileName2, ResultFileName])); 

  inherited;
end;

end.
