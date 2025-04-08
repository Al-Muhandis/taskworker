unit filetaskworker;

{$mode objfpc}{$H+}

interface

uses
  Classes, windows, SysUtils, fpjson, jsonparser, taskworker
  ;

type

  TTaskName = String[64];

  { TTaskFile }

  TTaskFile = class
  private
    FFileName: TTaskName;
  public
    constructor Create(const aFileName: String);
    property FileName: TTaskName read FFileName write FFileName;
  end;

  { TgFileTaskWorkerThread }

  generic TgFileTaskWorkerThread<TTask: TObject>= class(specialize TgTaskWorkerThread<TTaskFile>)
  type
    TProcessTaskEvent = procedure (aTask: TTask; var aIsOk: Boolean) of object;
  private
    FDeleteProcessed: Boolean;
    FOnProcessTask: TProcessTaskEvent;
    FPoolSubDir: String;
    FRootPoolDir: String;
    FSpoolDir: string;
    FProcessedDir: string;  
    FErrorDir: string;
    procedure EnsureDirsExist;
    function GetTaskName: String;
    function LoadTaskFromFile(const aTaskName: string; aObject: TTask): Boolean;
    procedure SaveJSONToFile(const aJSON: String);         
    procedure DeleteProcessedTask(const aTaskName: string);
    procedure MoveProcessedTask(const aTaskName: string; aIsOk: Boolean);
  protected
    procedure BeforeStart; override;               
    procedure DoProcessTask(aTask: TTask; out aIsOk: Boolean); virtual;
    procedure ProcessTask(aTask: TTaskFile); override; final;
  public
    constructor Create; override;
    procedure SendTask(aTask: TTask);
    property OnProcessTask: TProcessTaskEvent read FOnProcessTask write FOnProcessTask;
    property RootPoolDir: String read FRootPoolDir write FRootPoolDir;                 
    property PoolSubDir: String read FPoolSubDir write FPoolSubDir;
    property DeleteProcessed: Boolean read FDeleteProcessed write FDeleteProcessed;
  end;

implementation

uses
  fpjsonrtti
  ;

{ TTaskFile }

constructor TTaskFile.Create(const aFileName: String);
begin
  FFileName:=aFileName;
end;

{ TgFileTaskWorkerThread }

procedure TgFileTaskWorkerThread.EnsureDirsExist;
begin
  if not DirectoryExists(FSpoolDir) then
    ForceDirectories(FSpoolDir);
  if not DirectoryExists(FProcessedDir) then
    ForceDirectories(FProcessedDir);
  if not DirectoryExists(FErrorDir) then
    ForceDirectories(FErrorDir);
end;

function TgFileTaskWorkerThread.GetTaskName: String;
var
  aCode: Integer;
  aGUID: TGUID;
begin
  aCode:=CreateGUID(aGUID);
  if aCode<>0 then
  begin
    Logger.Error('GetTaskName. GUID creation error');
    Exit(EmptyStr);
  end;
  Result:=GUIDToString(aGUID);
end;

function TgFileTaskWorkerThread.LoadTaskFromFile(const aTaskName: string; aObject: TTask): Boolean;
var
  aJSONStr: TStringList;
  aDestreamer: TJSONDeStreamer;
begin
  Result:=False;
  try
    aJSONStr := TStringList.Create;
    try
      aJSONStr.LoadFromFile(FSpoolDir + aTaskName+'.json');
      aDestreamer:=TJSONDeStreamer.Create(nil);
      try
        aDestreamer.JSONToObject(aJSONStr.Text, aObject);
        Result:=True;
      finally
        aDestreamer.Free;
      end;
    finally
      aJSONStr.Free;
    end;
  except
    on E: Exception do
      Logger.Error('Error loading task file %s: %s', [aTaskName, E.Message]);
  end;
end;

procedure TgFileTaskWorkerThread.SaveJSONToFile(const aJSON: String);
var
  aJSONStr: TStringList;
  aStreamer: TJSONStreamer;
  aTempFileName, aTaskName: String;
begin
  aJSONStr := TStringList.Create;
  try
    aStreamer:=TJSONStreamer.Create(nil);
    try
      try
        aJSONStr.Text:=aJSON;
        aTempFileName:=GetTempFileName;
        aJSONStr.SaveToFile(aTempFileName);
        aTaskName:=GetTaskName;
        if not RenameFile(aTempFileName, Format(FSpoolDir+'%s.json', [aTaskName])) then
        begin
          Logger.Error('SendTask. Cannot rename file. Old file: %s, new file: %s', [aTempFileName, aTaskName]);
          Exit;
        end;
        PushTask(TTaskFile.Create(aTaskName));
      except
        on E: Exception do
          Logger.Error('SaveTaksToFile, task streaming & saving. %s: %s', [E.ClassName, E.Message]);
      end;
    finally
      aStreamer.Free;
    end;
  finally
    aJSONStr.Free;
  end;
end;

procedure TgFileTaskWorkerThread.DeleteProcessedTask(const aTaskName: string);
begin
  if not DeleteFile(FSpoolDir+aTaskName+'.json') then
    Logger.Error('Can''t delete task %s', [aTaskName]);
end;

procedure TgFileTaskWorkerThread.MoveProcessedTask(const aTaskName: string; aIsOk: Boolean);
var
  aNewDir: String;
begin
  try
    if aIsOk then
      aNewDir:=FProcessedDir+aTaskName+'.json'
    else
      aNewDir:=FErrorDir+aTaskName+'.json';
    RenameFile(FSpoolDir+aTaskName+'.json', aNewDir);
  except
    on E: Exception do
      Logger.Error('Error moving task file %s: %s', [aTaskName, E.Message]);
  end;
end;

procedure TgFileTaskWorkerThread.DoProcessTask(aTask: TTask; out aIsOk: Boolean);
begin
  aIsOk:=False;
  if Assigned(FOnProcessTask) then
    FOnProcessTask(aTask, aIsOk);
end;

procedure TgFileTaskWorkerThread.BeforeStart;
begin
  inherited BeforeStart;
  FSpoolDir := IncludeTrailingPathDelimiter(IncludeTrailingPathDelimiter(FRootPoolDir)+FPoolSubDir);
  FProcessedDir := FSpoolDir + 'processed'+DirectorySeparator;
  FErrorDir := FSpoolDir + 'error'+DirectorySeparator;
  EnsureDirsExist;
end;

procedure TgFileTaskWorkerThread.ProcessTask(aTask: TTaskFile);
var
  aTaskData: TTask;
  aIsOk: Boolean;
begin
  aTaskData:=TTask.Create;
  try
    if LoadTaskFromFile(aTask.FileName, aTaskData) then
    begin
      Logger.Info('Processing task from file: ' + aTask.FileName);
      try
        DoProcessTask(aTaskData, aIsOk);
      except
        on E: Exception do begin
          aIsOk:=False;
          Logger.Error('An error occurs while process event. %s: %s', [E.ClassName, E.Message]);
        end;
      end;
      MoveProcessedTask(aTask.FileName, aIsOk);
      if FDeleteProcessed and aIsOk then    // if there is an error while process event the task must be in the error folder
        DeleteProcessedTask(aTask.FileName);
    end
    else
      Logger.Error('Can''t load task file %s', [ATask.FileName]);
  finally
    aTaskData.Free;
    aTask.Free;
  end;
end;

constructor TgFileTaskWorkerThread.Create;
begin
  inherited Create;
  FRootPoolDir:={$IFDEF MSWINDOWS}'C:\ProgramData\Spool\'{$ENDIF}{$IFDEF UNIX}'/var/spool/'{$ENDIF};
  FPoolSubDir:='tasks';
end;

procedure TgFileTaskWorkerThread.SendTask(aTask: TTask);
var
  aStreamer: TJSONStreamer;
begin
  aStreamer:=TJSONStreamer.Create(nil);
  try
    try
      SaveJSONToFile(aStreamer.ObjectToJSONString(aTask));
    except
      on E: Exception do
        Logger.Error('SaveTaksToFile, task streaming & saving. %s: %s', [E.ClassName, E.Message]);
    end;
  finally
    aStreamer.Free;
  end;
end;

end.

