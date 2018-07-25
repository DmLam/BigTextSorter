unit UnitSorter;

interface
uses
  Windows, SysUtils, Classes,
  Common, UnitBlockSorter, UnitMerger, UnitMemoryManager;

procedure InitSort;
procedure SortData(const InFileName, OutFileName: string);
function GetMaxSortMemoryUsage: integer;
function GetMaxMergeMemoryUsage: integer;

implementation
uses
  UnitSplitter, UnitBlockList;

var
  ConsoleX, ConsoleY: integer;
  CurPercent: integer;
  MaxThreadRunning: integer = 0;
  MaxSortMemoryUsage : integer = 0;
  MaxMergeMemoryUsage: integer = 0;

function GetMaxSortMemoryUsage: integer;
begin
  Result := MaxSortMemoryUsage;
end;

function GetMaxMergeMemoryUsage: integer;
begin
  Result := MaxMergeMemoryUsage;
end;

function Max(const a, b: integer): integer;
begin
  Result := a;
  if b > a then
    Result := b;
end;

procedure OnProgress(const Percent: Double);
var
  NewPercent: integer;
begin
  if Debug then
    Exit;

  NewPercent := trunc(Percent * 100000);

  if NewPercent > CurPercent then
  begin
    CurPercent := NewPercent;
    if not Debug then
      SetConsoleCursorPos(ConsoleX, ConsoleY);

    write(Format('%d.%.3d%%', [CurPercent div 1000, CurPercent mod 1000]));
    if TrackMemoryUsage then
    begin
      if not Debug then
        write(Format(' (%5d KB of heap is in use, %5d KB max)',
          [GetMemoryUsage div 1024,
           Max(MaxSortMemoryUsage, GetMaxMemoryUsage) div 1024]));
    end;
  end;
end;

const
  WRITE_BUFFER_RATIO = 3;   // буфер на запись при слиянии во WRITE_BUFFER_RATIO раз больше буфера слияния

procedure InitSort;
var
  MaxMem: integer;
begin
  // Настройки размеров буферов
  // Здесь не учитывается размер памяти, нужный под хранение номеров созданных временных файлов (BlockList)
  // при больших размерах файла он имеет значение
  MaxMem := MemoryAvailable * 1024;

  SortBufferSize := MaxMem div 3;
  MergeBufferSize := MaxMem div (1 + (2 + WRITE_BUFFER_RATIO) * MaxWorkerThreadCount);
  MergeWriteBufferSize := MergeBufferSize * WRITE_BUFFER_RATIO;
end;

procedure SortData(const InFileName, OutFileName: string);
var
  BlockCount: integer;
  LastBlockFileName: string;
begin
  Blocks := TBlockList.Create(InFileName);   // список номеров созданных в процессе работы временных файлов
  try
    GetConsoleCursorPos(ConsoleX, ConsoleY);
    ShowConsoleCursor(false);
    try
      CurPercent := 0;

      BlockCount := SplitFileIntoSortedBlocks(InFileName, OnProgress);
      MaxSortMemoryUsage := GetMaxMemoryUsage;
      ResetMaxMemoryUsage;
      if BlockCount > 0 then // BlockCount = 0 ==> ошибка при разбиении (н-р, не смогли открыть входной файл)
      begin
        LastBlockFileName := MergeBlocks(OnProgress);
        MaxMergeMemoryUsage := GetMaxMemoryUsage;

        if FileExists(OutFileName) then
          DeleteFile(OutFileName);
        if Debug then
          CopyFile(PChar(LastBlockFileName), PChar(OutFileName), false)
        else
          RenameFile(LastBlockFileName, OutFileName);
      end;

      SetConsoleCursorPos(ConsoleX, ConsoleY);
      write(StringOfChar(' ', 50));
      SetConsoleCursorPos(ConsoleX, ConsoleY);
    finally
      ShowConsoleCursor(true);
    end;
  finally
    Blocks.Free;
  end;
end;


end.
