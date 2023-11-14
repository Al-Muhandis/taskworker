unit taskworker;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, eventlog
  ;

type

  { TgTaskWorkerThread }

  generic TgTaskWorkerThread<T> = class(TThread)
  private
    FLogger: TEventLog;
    FCount: Integer;
    FThreadList: TThreadList;
    FUnblockEvent: pRTLEvent;  // or defrosting and terminating while the thread is pending tasks
    FTerminateEvent: pRTLEvent;   // for terminating while the thread is delayed
    procedure ClearTasks;
    function PopTask: T;
    function WaitingForTask: Boolean;
  protected
    procedure ProcessTask(ATask: T); virtual; abstract;
    function WaitingDelay(ADelay: Integer): Boolean;
    property ThreadList: TThreadList read FThreadList write FThreadList;
  public
    constructor Create; virtual;
    destructor Destroy; override;
    procedure Execute; override;
    procedure PushTask(ATask: T);
    procedure TerminateWorker;
    property Count: Integer read FCount;
    property Logger: TEventLog read FLogger;
  end;

implementation

{ TgTaskWorkerThread }

function TgTaskWorkerThread.WaitingForTask: Boolean;
begin
  RTLeventWaitFor(FUnblockEvent);
  RTLeventResetEvent(FUnblockEvent);
  Result:=not Terminated;
end;

function TgTaskWorkerThread.WaitingDelay(ADelay: Integer): Boolean;
begin
  RTLeventWaitFor(FTerminateEvent, ADelay);
  Result:=not Terminated;
end;

function TgTaskWorkerThread.PopTask: T;
var
  AList: TList;
  i: Integer;
begin
  Result:=nil;
  AList:=FThreadList.LockList;
  i:=AList.Count;
  if i>0 then
  begin
    Result:=T(AList[0]);
    AList.Delete(0);
  end;
  FCount:=AList.Count;
  FThreadList.UnlockList;
end;

procedure TgTaskWorkerThread.ClearTasks;
var
  ATask: T;
begin
  repeat
     ATask:=PopTask;
     if Assigned(ATask) then
     begin
       { TODO : Save tasks for futher processing (for example after thread restart) }
       ATask.Free;
     end;
  until ATask=nil;
end;

constructor TgTaskWorkerThread.Create;
begin
  inherited Create(True);
  FreeOnTerminate:=False;
  FThreadList:=TThreadList.Create;
  FUnblockEvent:=RTLEventCreate;
  FTerminateEvent:=RTLEventCreate;
  FCount:=0;
  FLogger:=TEventLog.Create(nil);
end;

destructor TgTaskWorkerThread.Destroy;
begin
  FLogger.Free;
  RTLeventdestroy(FTerminateEvent);
  RTLeventdestroy(FUnblockEvent);
  FThreadList.Free;
  inherited Destroy;
end;

procedure TgTaskWorkerThread.Execute;
var
  ATask: T;
begin
  while not Terminated do
  begin
    if not WaitingForTask then break;
    repeat
      ATask:=PopTask;
      if Assigned(ATask) then
        ProcessTask(ATask);
    until (ATask=nil) or Terminated;
  end;
  ClearTasks;
end;

procedure TgTaskWorkerThread.PushTask(ATask: T);
begin
  FThreadList.Add(ATask);
  Inc(FCount);
  RTLeventSetEvent(FUnblockEvent);
end;

procedure TgTaskWorkerThread.TerminateWorker;
begin
  Terminate;
  RTLeventSetEvent(FUnblockEvent);
  RTLeventSetEvent(FTerminateEvent);
end;

end.

