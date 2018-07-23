unit UnitBlockList;

interface
uses
  Windows, SysUtils, Classes, SyncObjs,
  UnitThreadManager;

type
  TBlockList = class
  private
    FList: TList;
    FLockCS: TCriticalSection;
    FLastNumber: integer;
    FFileNameTemplate: string;

    function GetBlockNumber(Index: integer): integer; // последний использованный индекс для генерации имени файла
  public
    constructor Create(const TemplateFileName: string);
    destructor Destroy; override;

    procedure Lock;
    procedure UnLock;

    function NextBlockNumber: integer;
    function Add(const Thread: TProtoThread): string;
    procedure Delete;
    property BlockNumber[Index: integer]: integer
      read GetBlockNumber;
    function Count: integer;
    function FileName(const Number: integer): string;
  end;

var
  Blocks: TBlockList;

implementation

{ TBlockList }

function TBlockList.Add(const Thread: TProtoThread): string;
begin
  Result := Format(FFileNameTemplate, [Thread.BlockIndex]);

  Lock;
  try
    FList.Add(pointer(Thread.BlockIndex));
  finally
    UnLock;
  end;
end;

function TBlockList.Count: integer;
begin
  Result := FList.Count;
end;

constructor TBlockList.Create(const TemplateFileName: string);
begin
  FList := TList.Create;
  FLockCS := TCriticalSection.Create;
  FFileNameTemplate := ChangeFileExt(TemplateFileName, '.%.7d');
  FLastNumber := 0;
end;

procedure TBlockList.Delete;
begin
  Lock;
  try
    FList.Delete(0);
  finally
    Unlock;
  end;
end;

destructor TBlockList.Destroy;
begin
  FLockCS.Free;
  FList.Free;

  inherited;
end;

function TBlockList.FileName(const Number: integer): string;
begin
  Result := Format(FFileNameTemplate, [Number])
end;

function TBlockList.GetBlockNumber(Index: integer): integer;
begin
  Result := integer(FList[Index]);
end;

procedure TBlockList.Lock;
begin
  FLockCS.Enter;
end;

function TBlockList.NextBlockNumber: integer;
begin
  Result := InterlockedIncrement(FLastNumber);
end;

procedure TBlockList.UnLock;
begin
  FLockCS.Leave;
end;

end.
