unit UnitMerger;

interface
uses
  Windows, SysUtils, Classes, SyncObjs,
  Common, UnitBlockList, UnitBlockMerger;

  function MergeBlocks(const OnProgress: TProgressProc = nil): string;

implementation

function MergeBlocks(const OnProgress: TProgressProc = nil): string;
var
  StartBlockCount: integer;
  BlockIndex: integer;
  BlockMerger: TBlockMerger;
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
        BlockIndex := Blocks.BlockNumber[1];
        FileName2 := Blocks.FileName(BlockIndex);
      finally
        Blocks.UnLock;
      end;
      BlockIndex := Blocks.NextBlockNumber;
      MergedFileName := Blocks.FileName(BlockIndex);
      BlockMerger := TBlockMerger.Create(BlockIndex, FileName1, FileName2, MergedFileName);

      Blocks.Delete;
      Blocks.Delete;
      BlockMerger.ResultFileName := Blocks.Add(BlockMerger);
      BlockMerger.Execute;

      if Assigned(OnProgress) then
        OnProgress(0.5 + (1 - Blocks.Count / StartBlockCount) / 2);
    end;

    Result := Blocks.FileName(Blocks.BlockNumber[0]);
  end;
end;

end.
