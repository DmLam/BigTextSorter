unit UnitMemoryManager;

interface

procedure SetDebugMemoryManager;
procedure RestoreMemoryManager;
function GetMaxMemoryUsage: Cardinal;
procedure ResetMaxMemoryUsage;
function GetMemoryUsage: Cardinal;

var
  DebugTest: boolean = false;

implementation

var
  SystemMemoryManager : TMemoryManagerEx;
  MemoryUsage: Cardinal;
  MaxMemoryUsage: Cardinal;

function GetMaxMemoryUsage: Cardinal;
begin
  Result := MaxMemoryUsage;
end;

procedure ResetMaxMemoryUsage;
begin
  MaxMemoryUsage := 0;
end;

function GetMemoryUsage: Cardinal;
var
  MMS: TMemoryManagerState;
  sb: TSmallBlockTypeState;
begin
  GetMemoryManagerState(MMS);

  Result := MMS.TotalAllocatedMediumBlockSize + MMS.TotalAllocatedLargeBlockSize;
  for sb in MMS.SmallBlockTypeStates do
    Result := Result + sb.UseableBlockSize * sb.AllocatedBlockCount;
end;

procedure UpdateStatistics;
begin
  MemoryUsage := GetMemoryUsage;

  if MemoryUsage > MaxMemoryUsage then
    MaxMemoryUsage := MemoryUsage;
end;

function DebugGetMem(Size: Integer): Pointer;
begin
  Result := SystemMemoryManager.GetMem(Size);

  UpdateStatistics;
end;

function DebugFreeMem(P: Pointer): Integer;
begin
  Result := SystemMemoryManager.FreeMem(P);
end;

function DebugReallocMem(P: Pointer; Size: Integer): Pointer;
begin
  Result := SystemMemoryManager.ReallocMem(P, Size);

  UpdateStatistics;
end;

function DebugAllocMem(Size: Cardinal): Pointer;
begin
  Result := SystemMemoryManager.AllocMem(Size);

  UpdateStatistics;
end;

procedure SetDebugMemoryManager;
var
  DebugMemoryManager: TMemoryManagerEx;
begin
  GetMemoryManager(SystemMemoryManager);

  DebugMemoryManager.GetMem := DebugGetMem;
  DebugMemoryManager.FreeMem := DebugFreeMem;
  DebugMemoryManager.ReallocMem := DebugReallocMem;
  DebugMemoryManager.AllocMem := DebugAllocMem;
  DebugMemoryManager.RegisterExpectedMemoryLeak := SystemMemoryManager.RegisterExpectedMemoryLeak;
  DebugMemoryManager.UnregisterExpectedMemoryLeak := SystemMemoryManager.UnregisterExpectedMemoryLeak;

  SetMemoryManager(DebugMemoryManager);
end;

procedure RestoreMemoryManager;
begin
  SetMemoryManager(SystemMemoryManager);
end;


initialization
  MemoryUsage := 0;
  MaxMemoryUsage := 0;

end.
