program Sorter;

{$APPTYPE CONSOLE}

// »спользуетс€ сортировка сли€нием.
// »де€ стандартна€ - разбиваем исходный файл на блоки примерно равной длины по <= SORT_BLOCK_SIZE байт
//  аждый блок сортируем в пам€ти и сохран€ем во временный файл
// ƒальше сливаем блоки с сортировкой
//
// ћожно уменьшить количество используемого дискового пространства если запускать сли€ние
// не дожида€сь окончани€ процесса разбиени€, но там будет больше проблем с управлением
// потоками, поэтому пока так
//
// ”величение количества рабочих потоков вызывает уменьшение скорости из-за конкуренции за диск между потоками

uses
  Windows,
  SysUtils,
  UnitSorter in 'UnitSorter.pas',
  UnitBlockSorter in 'UnitBlockSorter.pas',
  UnitWorker in 'UnitWorker.pas',
  UnitSplitter in 'UnitSplitter.pas',
  UnitMerger in 'UnitMerger.pas',
  UnitBlockMerger in 'UnitBlockMerger.pas',
  Common in 'Common.pas',
  UnitMemoryManager in 'UnitMemoryManager.pas',
  UnitBufferedFileStream in 'UnitBufferedFileStream.pas',
  UnitBlockList in 'UnitBlockList.pas';

procedure ParseParams(var InFile, OutFile: string);
var
  OptionsStartIndex, i: integer;
  Option: string;
  n: integer;
begin
  InFile := ParamStr(1);
  if ParamCount = 1 then
    OutFile := InFile
  else
  begin
    OutFile := ParamStr(2);
    if OutFile[1] = '-' then
    begin
      OptionsStartIndex := 2;
      OutFile := InFile;
    end
    else
      OptionsStartIndex := 3;

    for i := OptionsStartIndex to ParamCount do
    begin
      Option := ParamStr(i);

      if (Option[1] = '-') and (Length(Option) > 1) then
      begin
        Delete(Option, 1, 1);
        if SameText(Option, 'D') then
          Debug := true
        else
        if SameText(Option, 'M') then
          TrackMemoryUsage := true
        else
        if UpCase(Option[1]) = 'T' then
        begin
          Delete(Option, 1, 1);
          if TryStrToInt(Option, n) then
            MaxWorkerThreadCount := n
          else
            writeln('Incorrect -T option value. Using ', MaxWorkerThreadCount, ' worker treads by default');
        end
        else
        if UpCase(Option[1]) = 'L' then
        begin
          Delete(Option, 1, 1);
          if TryStrToInt(Option, n) then
            MemoryAvailable := n
          else
            writeln('Incorrect -L option value. Using ', MemoryAvailable, ' by default');
        end;
      end;
    end;

    if Debug then
      TrackMemoryUsage := false;
  end;
end;

var
  InFile, OutFile: string;
  Freq, StartTime, EndTime: Int64;
  InFileSize, OutFileSize: Int64;

begin
  if ParamCount = 0 then
  begin
    writeln('Text file sorter');
    writeln('Usage: sorter InFile [OutFile] [Options]');
    writeln('Options:');
    writeln('  -D - debug (shows log and saves all the temporary files, be careful!)');
    writeln('  -M - track memory usage (doesn''t work with -D)');
    writeln('  -Tn - use n worker threads (default ', MaxWorkerThreadCount, ')');
    writeln('  -Ln - limit memory usage to n kilobytes (default ', MemoryAvailable, ')');
  end
  else
  begin
    ParseParams(InFile, OutFile);

    if not FileExists(InFile) then
    begin
      writeln('File not found ', InFile);
      Exit;
    end;

    InFileSize := FileSize(InFile);

    if TrackMemoryUsage then
      SetDebugMemoryManager;

    write('Sorting ', InFile);
    if TrackMemoryUsage then
      writeln(' using ', MemoryAvailable, ' Kb of memory')
    else
      writeln;

    InitSort;

    if TrackMemoryUsage then
      writeln('Buffers size: sort ', SortBufferSize, ', merge ', MergeBufferSize);

    QueryPerformanceFrequency(Freq);
    QueryPerformanceCounter(StartTime);

    try
      SortData(InFile, OutFile);
    except
      on E: EOutOfMemory do
      begin
        writeln('Out of memory');
        Exit;
      end
      else
        raise
    end;

    QueryPerformanceCounter(EndTime);

    OutFileSize := FileSize(OutFile);

    writeln(Format('Done in %.3f seconds                                                                         ', [(EndTime - StartTime) / Freq]));

    if TrackMemoryUsage then
    begin
      writeln('Input file size : ', InFileSize, ' bytes');
      writeln('Output file size: ', OutFileSize, ' bytes');
      writeln('Max heap usage: sorting ', GetMaxSortMemoryUsage div 1024, ' KBytes, merging ', GetMaxMergeMemoryUsage div 1024, ' KBytes');

      RestoreMemoryManager;
    end;
  end;
end.
