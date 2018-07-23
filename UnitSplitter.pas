unit UnitSplitter;

interface
uses
  Windows, SysUtils, Classes,
  Common, UnitBlockList, UnitBlockSorter, UnitThreadManager;

function SplitFileIntoSortedBlocks(const FileName: string; const ThreadManager: TThreadManager; const OnProgress: TProgressProc = nil): integer;

implementation

uses UnitMemoryManager, UnitMerger;

procedure ClearFiles;
begin
  while Blocks.Count > 0 do
  begin
    DeleteFile(Blocks.FileName(Blocks.BlockNumber[0]));
    Blocks.Delete;
  end;
end;

{ TSplitter }

function SplitFileIntoSortedBlocks(const FileName: string; const ThreadManager: TThreadManager; const OnProgress: TProgressProc = nil): integer;
var
  FS: TStream;
  Buf, BufStart, BufEnd, LastChar: PAnsiChar;
  ReadCnt, BlockSize: integer;
  BlockRestSize: integer;
  Block: PAnsiChar;
  BlockIndex: integer;
  BlockSorter: TBlockSorterThread;
  Error: boolean;
begin
  Result := 0;

  try
    FS := TFileStream.Create(FileName, fmOpenRead);
  except
    writeln('Cannot open file ', FileName);

    Exit;
  end;
  try
    Error := false;
    Block := nil;
    BlockSize := 0;

    GetMem(Buf, SortBufferSize);
    try
      BufStart := Buf;
      BlockRestSize := 0; // ������ ������ ������, ����������� ����������� � ����� �� ���������� �������
      repeat
        ReadCnt := FS.Read(BufStart^, SortBufferSize - BlockRestSize) + BlockRestSize;
        if ReadCnt > 0 then
        begin
          if ReadCnt > 1 then
          begin
            BufEnd := Buf + ReadCnt;
            // ������ ��������� ��������� ������ � �����
            LastChar := FindLastCRLF(Buf, BufEnd);
            if LastChar = nil then
            begin
              // ���� � ������ �� ����� �������� ������ ������ � ����� ���� ������� ������� ������, �� ��������� � �����
              writeln('Line too long!');
              Error := true;
              Break;
            end;
            // ���������� ���� ��� ���������� - ������� ���� ��� �� ���������� �������� ������
            Inc(LastChar, 2);  // CRLF
            BlockSize := LastChar - Buf;
            GetMem(Block, BlockSize);
            Move(Buf^, Block^, BlockSize);
            // ������� ����� �������� ������ ��������� � ������ ������ ��� ���������� �����
            BlockRestSize := BufEnd - LastChar;
            Move(LastChar^, Buf^, BlockRestSize);
            BufStart := Buf + BlockRestSize;
          end
          else
          if ReadCnt = 1 then
          begin
            BlockSize := 1;
            GetMem(Block, 1);
            Block^ := Buf^;
            BlockRestSize := 0;
          end;

          // ����������� � �������� � ����
          Inc(Result);
          BlockIndex := Blocks.NextBlockNumber;
          BlockSorter := TBlockSorterThread.Create(Block, BlockSize, BlockIndex);
          BlockSorter.ResultFileName := Blocks.Add(BlockSorter);
          ThreadManager.Run(BlockSorter);
          if Assigned(OnProgress) then
            OnProgress(FS.Position / FS.Size / 2);
        end;
      until ReadCnt = 0;

      if Error then
      begin
        ThreadManager.WaitAllThreads;
        ClearFiles;
        Result := 0;
      end;
    finally
      FreeMem(Buf);
    end;
  finally
    FS.Free;
  end;
end;

end.
