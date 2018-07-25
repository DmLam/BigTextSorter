unit UnitWorker;

interface
uses
  Windows, SysUtils, Classes,
  Common;

type
  TWorker = class
  private
    FBlockIndex: integer;
    FResultFileName: string;

  public
    constructor Create(const BlockIndex: integer);
    procedure Execute; virtual; abstract;

    property BlockIndex: integer
      read FBlockIndex;
    property ResultFileName: string
      read FResultFileName write FResultFileName;
  end;

implementation

{ TWorker }

constructor TWorker.Create(const BlockIndex: integer);
begin
  FBlockIndex := BlockIndex;
end;

end.
