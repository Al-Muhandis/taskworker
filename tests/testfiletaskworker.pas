unit testfiletaskworker;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, fpcunit, testregistry, filetaskworker
  ;

type

  { TSampleTask }

  TSampleTask = class
  private
    FSomeIntProperty: Integer;
    FSomeStringProperty: String;
  published
    property SomeStringProperty: String read FSomeStringProperty write FSomeStringProperty;
    property SomeIntProperty: Integer read FSomeIntProperty write FSomeIntProperty;
  end;

  TTestFileTaskWorkerThread = specialize TgFileTaskWorkerThread<TSampleTask>;

  { TBaseTestFileTask }

  TBaseTestFileTask=class(TTestCase) // abstract class
  private
    FWorker: TTestFileTaskWorkerThread;
  protected
    procedure SetUp; override;
    procedure TearDown; override;                                                   
    class procedure TestFileTaskProcessTask(aTask: TSampleTask; var aIsOk: Boolean);
  published
    procedure ProcessTask;
  end;

  { TTestFileTaskEvent }

  TTestFileTaskEvent= class(TBaseTestFileTask)
  protected
    procedure SetUp; override;
  end;

  { TTestFileTaskWorkerThreadOverride }

  TTestFileTaskWorkerThreadOverride = class(specialize TgFileTaskWorkerThread<TSampleTask>)
  protected
    procedure DoProcessTask(aTask: TSampleTask; out aIsOk: Boolean); override;
    function GetTaskName(aTask: TSampleTask): TTaskName; override;
  public
    FTestCase: TTestCase;
  end;

  { TTestFileTaskOverride }

  TTestFileTaskOverride= class(TBaseTestFileTask)
  protected
    procedure SetUp; override;
  end;

implementation

uses
  eventlog
  ;

const
  _SomeInt=777;  
  _SomeStr='Some string value!';

{ TBaseTestFileTask }

class procedure TBaseTestFileTask.TestFileTaskProcessTask(aTask: TSampleTask; var aIsOk: Boolean);
begin
  aIsOk:=True;
  AssertEquals(Format('SomeIntValue must be %d', [_SomeInt]), _SomeInt, aTask.SomeIntProperty);
  AssertEquals(Format('SomeStrValue must be %s', [_SomeStr]), _SomeStr, aTask.SomeStringProperty);
end;

procedure TBaseTestFileTask.ProcessTask;
var
  aTask: TSampleTask;
begin
  aTask:=TSampleTask.Create;
  try
    aTask.SomeIntProperty:=_SomeInt;
    aTask.SomeStringProperty:=_SomeStr;
    FWorker.SendTask(aTask);
  finally
    aTask.Free;
  end;
end;

procedure TBaseTestFileTask.SetUp;
begin
  { #Warning: Must be overriden by ancestor where FWorker must be created! }
  FWorker.Logger.AppendContent:=True;
  FWorker.Logger.LogType:=ltFile;
  FWorker.LoadTasksOnStart:=True;
  FWorker.Start;
end;

procedure TBaseTestFileTask.TearDown;
begin
  FWorker.TerminateWorker;
  FWorker.WaitFor;
  FWorker.Free;
end;

procedure TTestFileTaskEvent.SetUp;
begin
  FWorker:=TTestFileTaskWorkerThread.Create;
  FWorker.OnProcessTask:=@TestFileTaskProcessTask;
  inherited;
end;

{ TTestFileTaskWorkerThreadOverride }

procedure TTestFileTaskWorkerThreadOverride.DoProcessTask(aTask: TSampleTask; out aIsOk: Boolean);
begin
  inherited;
  TTestFileTaskOverride.TestFileTaskProcessTask(aTask, aIsOk);
end;

function TTestFileTaskWorkerThreadOverride.GetTaskName(aTask: TSampleTask): TTaskName;
begin
  Result:=aTask.SomeIntProperty.ToString;
end;

{ TTestFileTaskOverride }

procedure TTestFileTaskOverride.SetUp;
begin
  FWorker:=TTestFileTaskWorkerThreadOverride.Create;
  inherited;
end;

initialization
  RegisterTests([TTestFileTaskEvent, TTestFileTaskOverride]);

end.

