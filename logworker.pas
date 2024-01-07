unit logworker;

{$mode ObjFPC}{$H+}

interface

uses
  Classes, SysUtils, taskworker
  ;

type

  { TLogEventTask }

  TLogEventTask = class(TPersistent)
  private
    FDateTime: TDateTime;
    FEventType: TEventType;
    FMessage: String;
  public
    procedure AssignTo(Dest: TPersistent); override;
    property Message: String read FMessage write FMessage;
    property EventType: TEventType read FEventType write FEventType;
    property DateTime: TDateTime read FDateTime write FDateTime;
  end;

  TCustomEventLogThread = specialize TgTaskWorkerThread<TLogEventTask>;

  { TEventLogThread }

  TEventLogThread = class(TCustomEventLogThread)
  protected
    procedure ProcessTask(ATask: TLogEventTask); override;
  end;

  TLogLevel = (llDebug, llInfo, llWarning, llError, llNone);

  { TThreadedEventLog }

  TThreadedEventLog = class(TPersistent)
  private
    FActive: Boolean;
    FAppendContent: Boolean;
    FEventLogThread: TEventLogThread;
    FFileName: String;
    FLogLevel: TLogLevel;
    FPaused: Boolean;
    function CanLog(aEventType: TEventType): Boolean;
    procedure EnsureActive;
  public
    constructor Create;
    destructor Destroy; override;          
    procedure Debug(const aMessage: String);
    procedure Error(const aMessage: String);
    Procedure Error (const aFormat : String; Args : Array of const);
    procedure Info(const aMessage: String);
    procedure Log(aEventType: TEventType; const aMessage: String);
    procedure Warning(const aMessage: String);
    property Active: Boolean read FActive;
    property AppendContent: Boolean read FAppendContent write FAppendContent;
    property EventLogThread: TEventLogThread read FEventLogThread;
    property LogLevel: TLogLevel read FLogLevel write FLogLevel;
    property FileName: String read FFileName write FFileName;
    property Paused: Boolean read FPaused write FPaused;
  end;

function LogLevelToString(aLogLevel: TLogLevel): String;
function StringToLogLevel(const S: String): TLogLevel;

implementation

uses
  eventlog
  ;

const
  _loglevelalias: array[TLogLevel] of String = ('debug', 'info', 'warning', 'error', '');

function LogLevelToString(aLogLevel: TLogLevel): String;
begin
  Result:=_loglevelalias[aLogLevel];
end;

function StringToLogLevel(const S: String): TLogLevel;
begin
  for Result in TLogLevel do
    if SameStr(S, _loglevelalias[Result]) then
      Exit;
end;

{ TLogEventTask }

procedure TLogEventTask.AssignTo(Dest: TPersistent);
var
  aDest: TLogEventTask;
begin
  if Dest is TLogEventTask then
  begin
    aDest:=TLogEventTask(Dest);
    aDest.FMessage:=FMessage;
    aDest.FEventType:=FEventType;
    aDest.FDateTime:=FDateTime;
  end
  else
    inherited AssignTo(Dest);
end;

{ TEventLogThread }

procedure TEventLogThread.ProcessTask(ATask: TLogEventTask);
begin
  try
    try
      Logger.Log(ATask.EventType, ' ['+FormatDateTime('yyyy-mm-dd hh:nn:ss.zzz', ATask.DateTime)+'] '+ATask.Message);
    finally
      ATask.Free;
    end;
  except
    on E: Exception do Logger.Error('Process task. '+E.Classname+': '+E.message);
  end;
end;

{ TThreadedEventLog }

function TThreadedEventLog.CanLog(aEventType: TEventType): Boolean;
begin
  if FLogLevel=llNone then
    Exit(False);
  case aEventType of
    etError:   Result:=FLogLevel<=llError;
    etWarning: Result:=FLogLevel<=llWarning;
    etInfo:    Result:=FLogLevel<=llInfo;
    etDebug:   Result:=FLogLevel<=llDebug;
  else
    Result:=FLogLevel<=llInfo;
  end;
end;

procedure TThreadedEventLog.EnsureActive;
begin
  if not Active then
  begin
    FEventLogThread.Logger.FileName:=FFileName;
    FEventLogThread.Logger.LogType:=ltFile;
    FEventLogThread.Logger.AppendContent:=FAppendContent;
    FEventLogThread.Start;
    FActive:=True;
  end;
end;

constructor TThreadedEventLog.Create;
begin
  FActive:=False;
  FEventLogThread:=TEventLogThread.Create;
  FLogLevel:=llInfo;
end;

destructor TThreadedEventLog.Destroy;
begin
  FEventLogThread.TerminateWorker;
  FEventLogThread.Free;
  inherited Destroy;
end;

procedure TThreadedEventLog.Debug(const aMessage: String);
begin
  Log(etDebug, aMessage);
end;

procedure TThreadedEventLog.Error(const aMessage: String);
begin
  Log(etError, aMessage);
end;

procedure TThreadedEventLog.Error(const aFormat: String; Args: array of const);
begin
  Error(Format(aFormat, Args));
end;

procedure TThreadedEventLog.Info(const aMessage: String);
begin
  Log(etInfo, aMessage);
end;

procedure TThreadedEventLog.Log(aEventType: TEventType; const aMessage: String);
var
  aTask: TLogEventTask;
begin
  If Paused then
    Exit;
  if not CanLog(aEventType) then
    Exit;
  EnsureActive;
  aTask:=TLogEventTask.Create;
  aTask.DateTime:=Now;
  aTask.EventType:=aEventType;
  aTask.Message:=aMessage;
  FEventLogThread.PushTask(aTask);
end;

procedure TThreadedEventLog.Warning(const aMessage: String);
begin
  Log(etWarning, aMessage);
end;

end.

