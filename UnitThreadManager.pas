unit UnitThreadManager;

interface
uses
  Windows, SysUtils, Classes, SyncObjs,
  Common;

type
  TThreadManager = class;
  TProtoThread = class;
  
  TOnFinishEvent = procedure(const TProtoThread: TProtoThread);

  TProtoThread = class(TThread)
  private
    FIndex: integer;
    FBlockIndex: integer;
    FResultFileName: string;
    FManager: TThreadManager;
  public
    constructor Create(const BlockIndex: integer);
    destructor Destroy; override;

    procedure Execute; override;

    property Index: integer
      read FIndex;
    property BlockIndex: integer
      read FBlockIndex;
    property ResultFileName: string
      read FResultFileName write FResultFileName;
  end;

  TThreadManager = class
  private

    FPoolSize: integer;
    FPool: array of TProtoThread;
    FFinishEvents: array of TEvent;
    FRunning: integer;
    FRunningCS: TCriticalSection;

    const
      WAIT_FOR_ALL = true;
      WAIT_FOR_ANY = false;

    // ждет наступления или одного из или всех FinishEvents.
    // В первом случае возвращает индекс события  
    function WaitForEvents(const WaitForAll: boolean): integer;
    procedure OnThreadTerminate(Sender: TProtoThread);

  public
    constructor Create(const MaxPoolSize: integer);
    destructor Destroy; override;

    procedure Run(const Thread: TProtoThread);
    procedure WaitAllThreads;
    function ThreadByBlockIndex(const BlockIndex: integer): TProtoThread;

    property Running: integer
      read FRunning;
  end;

var
  ThreadManager: TThreadManager;

implementation

var
  ThreadIndex: integer;

{ TProtoThread }

constructor TProtoThread.Create(const BlockIndex: integer);
begin
  inherited Create(true);

  FreeOnTerminate := true;
  FManager := nil;
  FBlockIndex := BlockIndex;
  FIndex := InterlockedIncrement(ThreadIndex);
  Log(ClassName + ' created ' + IntToStr(FIndex));
end;

destructor TProtoThread.Destroy;
begin
  Log(ClassName + ' destroyed ' + IntToStr(FIndex));

  inherited;
end;

procedure TProtoThread.Execute;
begin
  Log('Thread finished ' + IntToStr(FIndex));

  if Assigned(FManager) then
    FManager.OnThreadTerminate(Self);
end;

{ TThreadManager }

constructor TThreadManager.Create(const MaxPoolSize: integer);
var
  i: Integer;
begin
  FPoolSize := MaxPoolSize;
  SetLength(FPool, FPoolSize);
  SetLength(FFinishEvents, FPoolSize);
  for i := 0 to FPoolSize - 1 do
    FFinishEvents[i] := TEvent.Create(nil, true, true, '');
  FRunning := 0;
  FRunningCS := TCriticalSection.Create;
end;

destructor TThreadManager.Destroy;
var
  i: Integer;
begin
  // Дождемся окончания всех запущенных на текущий момент потоков
  WaitForEvents(WAIT_FOR_ALL);
  for i := 0 to FPoolSize - 1 do
    FFinishEvents[i].Free;

  FRunningCS.Free;
  
  inherited;
end;

procedure TThreadManager.OnThreadTerminate(Sender: TProtoThread);
var
  i: integer;
begin
  for i := 0 to FPoolSize - 1 do
    if FPool[i] = Sender then
    begin
      FPool[i] := nil;
      FFinishEvents[i].SetEvent;
      InterlockedDecrement(FRunning);
      Break;
    end;
end;

procedure TThreadManager.Run(const Thread: TProtoThread);
var
  FreeSlotIndex: integer;
begin
  FRunningCS.Enter;
  try
    // если количество запущеных потоков максимально - дождемся освобождения какого-нибудь слота
    FreeSlotIndex := WaitForEvents(WAIT_FOR_ANY);
    FPool[FreeSlotIndex] := Thread;
    FFinishEvents[FreeSlotIndex].ResetEvent;

    // по своему окончанию поток вызовет событие OnThreadTerminate менеджера
    Thread.FManager := Self;

    InterlockedIncrement(FRunning);
    Thread.Resume;
  finally
    FRunningCS.Leave;
  end;
end;

function TThreadManager.ThreadByBlockIndex(const BlockIndex: integer): TProtoThread;
var
  i: integer;
begin
  Result := nil;
  for i := 0 to FPoolSize - 1 do
    if (FPool[i] <> nil) and (FPool[i].BlockIndex = BlockIndex) then
    begin
      Result := FPool[i];
      Break;
    end;
end;

procedure TThreadManager.WaitAllThreads;
begin
  WaitForEvents(WAIT_FOR_ALL);
end;

function TThreadManager.WaitForEvents(const WaitForAll: boolean): integer;
var
  H: array of THandle;
  i: Integer;
  R: DWORD;
begin
  Result := -1;
  SetLength(H, FPoolSize);
  for i := 0 to FPoolSize - 1 do
    H[i] := FFinishEvents[i].Handle;

  R := WaitForMultipleObjects(FPoolSize, @H[0], WaitForAll, INFINITE);
  if WaitForAll = WAIT_FOR_ANY then
    Result := R - WAIT_OBJECT_0;
end;

end.
