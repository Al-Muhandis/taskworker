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

  { TTestFileTask }

  TTestFileTask= class(TTestCase)
  private
    FFileTaskWorker: TTestFileTaskWorkerThread;
    procedure TestFileTaskProcessTask(aTask: TSampleTask; var aIsOk: Boolean);
  protected
    procedure SetUp; override;
    procedure TearDown; override;
  published
    procedure ProcessTask;
  end;

implementation

uses
  eventlog
  ;

const
  _SomeInt=777;  
  _SomeStr='Some string value!';

procedure TTestFileTask.ProcessTask;
var
  aTask: TSampleTask;
begin
  aTask:=TSampleTask.Create;
  try
    aTask.SomeIntProperty:=_SomeInt;
    aTask.SomeStringProperty:=_SomeStr;
    FFileTaskWorker.SendTask(aTask);
  finally                      
    aTask.Free;
  end;
end;

procedure TTestFileTask.TestFileTaskProcessTask(aTask: TSampleTask; var aIsOk: Boolean);
begin
  aIsOk:=True;
  AssertEquals(Format('SomeIntValue must be %d', [_SomeInt]), _SomeInt, aTask.SomeIntProperty); 
  AssertEquals(Format('SomeIntValue must be %s', [_SomeStr]), _SomeStr, aTask.SomeStringProperty);
end;

procedure TTestFileTask.SetUp;
begin
  FFileTaskWorker:=TTestFileTaskWorkerThread.Create;
  FFileTaskWorker.OnProcessTask:=@TestFileTaskProcessTask;
  FFileTaskWorker.Logger.AppendContent:=True;    
  FFileTaskWorker.Logger.LogType:=ltFile;
  FFileTaskWorker.Start;
end;

procedure TTestFileTask.TearDown;
begin
  FFileTaskWorker.TerminateWorker;
  FFileTaskWorker.WaitFor;
  FFileTaskWorker.Free;
end;

initialization
  RegisterTest(TTestFileTask);

end.

