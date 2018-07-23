unit UnitMerger;

interface
uses
  Windows, SysUtils, Classes, SyncObjs,
  Common, UnitThreadManager, UnitBlockList, UnitBlockMerger;

  function MergeBlocks(const OnProgress: TProgressProc = nil): string;

implementation

procedure OnBlocksMerged(const ProtoThread: TProtoThread);
begin
//  SetBlockFinished(ProtoThread);
end;

// Использовать Thread.WaitFor нельзя, т.к. у потоков установлено FreeOnTerminate и Free происходит быстрее, чем выход и WaitFor
procedure WaitForThread(const BlockIndex: integer);
begin
//  while Blocks.Objects[Index] <> nil do
//    Sleep(10);
  while ThreadManager.ThreadByBlockIndex(BlockIndex) <> nil do
    Sleep(10);
end;

function MergeBlocks(const OnProgress: TProgressProc = nil): string;
var
  StartBlockCount: integer;
  BlockIndex: integer;
  BlockMerger: TBlockMergerThread;
  FileName1, FileName2, MergedFileName: string;
begin
  Result := '';
  if Blocks.Count > 0 then
  begin
    StartBlockCount := Blocks.Count;
    while Blocks.Count > 1 do
    begin
      Blocks.Lock;
      try
        BlockIndex := Blocks.BlockNumber[0];
        FileName1 := Blocks.FileName(BlockIndex);
        WaitForThread(BlockIndex);
        BlockIndex := Blocks.BlockNumber[1];
        FileName2 := Blocks.FileName(BlockIndex);
        WaitForThread(BlockIndex);
      finally
        Blocks.UnLock;
      end;
      BlockIndex := Blocks.NextBlockNumber;
      MergedFileName := Blocks.FileName(BlockIndex);
      BlockMerger := TBlockMergerThread.Create(BlockIndex, FileName1, FileName2, MergedFileName);

      Blocks.Delete;
      Blocks.Delete;
      BlockMerger.ResultFileName := Blocks.Add(BlockMerger);
      ThreadManager.Run(BlockMerger);

      if Assigned(OnProgress) then
        OnProgress(0.5 + (1 - Blocks.Count / StartBlockCount) / 2);
    end;

    Result := Blocks.FileName(Blocks.BlockNumber[0]);
  end;
end;

end.
