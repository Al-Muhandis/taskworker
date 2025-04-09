unit filetaskworker;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, fpjson, jsonparser, taskworker
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

  TTaskResult = (trNone, trUnprocessed, trProcessed, trError);

  { TgFileTaskWorkerThread }

  generic TgFileTaskWorkerThread<TTask: TObject>= class(specialize TgTaskWorkerThread<TTaskFile>)
  type
    TProcessTaskEvent = procedure (aTask: TTask; var aIsOk: Boolean) of object;
  private
    FDeleteProcessed: Boolean;
    FLoadTasksOnStart: Boolean;
    FOnProcessTask: TProcessTaskEvent;
    FPoolSubDir: String;
    FRootPoolDir: String;
    FSpoolDir: string;
    FProcessedDir: string;  
    FErrorDir: string;
    procedure EnsureDirsExist;                                 
    function FileFromTaskName(const aTaskName: String; aTaskResult: TTaskResult = trUnprocessed): String;
    procedure FindFreeTaskName(var aTaskName: TTaskName; aTaskResult: TTaskResult = trUnprocessed);
    function GetGUIDTaskName: String;
    function LoadTaskFromFile(const aTaskName: string; aObject: TTask): Boolean;
    function SaveJSONToFile(const aJSON: String; const aTaskName: TTaskName): Boolean;
    procedure DeleteProcessedTask(const aTaskName: string);
    procedure MoveProcessedTask(const aTaskName: string; aIsOk: Boolean);
    procedure LoadAllTasks;
  protected
    procedure BeforeStart; override;               
    procedure DoProcessTask(aTask: TTask; out aIsOk: Boolean); virtual;
    function GetTaskName(aTask: TTask): TTaskName; virtual;
    procedure ProcessTask(aTask: TTaskFile); override; final;
  public
    constructor Create; override;
    procedure SendTask(aTask: TTask);
    property OnProcessTask: TProcessTaskEvent read FOnProcessTask write FOnProcessTask;
    property RootPoolDir: String read FRootPoolDir write FRootPoolDir;                 
    property PoolSubDir: String read FPoolSubDir write FPoolSubDir;
    property DeleteProcessed: Boolean read FDeleteProcessed write FDeleteProcessed;
    property LoadTasksOnStart: Boolean read FLoadTasksOnStart write FLoadTasksOnStart;
  end;

procedure FindAllFiles(const aDirectory, aFileMask: string; aFiles: TStringList);

implementation

uses
  fpjsonrtti
  ;

procedure FindAllFiles(const aDirectory, aFileMask: string; aFiles: TStringList);
var
  aSearchRec: TSearchRec;
begin
  if FindFirst(IncludeTrailingPathDelimiter(aDirectory) + aFileMask, faAnyFile, aSearchRec) = 0 then
  begin
    repeat
      if (aSearchRec.Attr and faDirectory = 0) then
        aFiles.Add(ChangeFileExt(aSearchRec.Name, EmptyStr));
    until FindNext(aSearchRec) <> 0;
  end;
  FindClose(aSearchRec);
end;

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

function TgFileTaskWorkerThread.FileFromTaskName(const aTaskName: String; aTaskResult: TTaskResult): String;
begin
  case aTaskResult of
    trProcessed: Result:=Format(FProcessedDir+'%s.json', [aTaskName]);
    trError:     Result:=Format(FErrorDir+'%s.json',     [aTaskName]);
  else
    Result:=Format(FSpoolDir+'%s.json', [aTaskName]);
  end;
end;

procedure TgFileTaskWorkerThread.FindFreeTaskName(var aTaskName: TTaskName; aTaskResult: TTaskResult);
var
  i: Integer;
  aNewTaskName: String;
begin
  i:=0;
  aNewTaskName:=aTaskName;
  while FileExists(FileFromTaskName(aNewTaskName, aTaskResult)) do
  begin
    Inc(i);
    aNewTaskName:=aTaskName+'_'+i.ToString;
  end;
  aTaskName:=aNewTaskName;
end;

function TgFileTaskWorkerThread.GetGUIDTaskName: String;
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
      aJSONStr.LoadFromFile(FileFromTaskName(aTaskName));
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

function TgFileTaskWorkerThread.SaveJSONToFile(const aJSON: String; const aTaskName: TTaskName): Boolean;
var
  aJSONStr: TStringList;
  aStreamer: TJSONStreamer;
  aTempFileName: String;
  aNewTaskName: TTaskName;
begin
  Result:=False;
  aJSONStr := TStringList.Create;
  try
    aStreamer:=TJSONStreamer.Create(nil);
    try
      try
        aJSONStr.Text:=aJSON;
        aTempFileName:=GetTempFileName;
        aJSONStr.SaveToFile(aTempFileName);
        aNewTaskName:=aTaskName;
        FindFreeTaskName(aNewTaskName);
        if not RenameFile(aTempFileName, FileFromTaskName(aNewTaskName)) then
        begin
          Logger.Error('SendTask. Cannot rename file. Old file: %s, new file: %s', [aTempFileName, aNewTaskName]);
          Exit;
        end;
        PushTask(TTaskFile.Create(aNewTaskName));
        Result:=True;
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
  if not DeleteFile(FileFromTaskName(aTaskName, trProcessed)) then
    Logger.Error('Can''t delete task %s', [aTaskName]);
end;

procedure TgFileTaskWorkerThread.MoveProcessedTask(const aTaskName: string; aIsOk: Boolean);
var
  aNewTaskName: TTaskName;
  aTaskResult: TTaskResult;
begin
  if aIsOk then
    aTaskResult:=trProcessed
  else
    aTaskResult:=trError;
  aNewTaskName:=aTaskName;
  FindFreeTaskName(aNewTaskName, aTaskResult);
  if not RenameFile(FileFromTaskName(aTaskName), FileFromTaskName(aNewTaskName, aTaskResult)) then
    Logger.Error('Can''t move task file %s to %s', [aTaskName, aNewTaskName]);
end;

procedure TgFileTaskWorkerThread.LoadAllTasks;
var
  aTaskFiles: TStringList;
  aFileName: String;
  aTaskFile: TTaskFile;
begin
  aTaskFiles:=TStringList.Create;
  try
    FindAllFiles(FSpoolDir, '*.json', aTaskFiles);
    if aTaskFiles.Count>0 then
      Logger.Warning('There are %d unprocessed task(s) found!', [aTaskFiles.Count]);
    for aFileName in aTaskFiles do
    begin
      aTaskFile:=TTaskFile.Create(aFileName);
      PushTask(aTaskFile);
    end;
  finally
    aTaskFiles.Free;
  end;
end;

procedure TgFileTaskWorkerThread.DoProcessTask(aTask: TTask; out aIsOk: Boolean);
begin
  aIsOk:=False;
  if Assigned(FOnProcessTask) then
    FOnProcessTask(aTask, aIsOk);
end;

function TgFileTaskWorkerThread.GetTaskName(aTask: TTask): TTaskName;
begin
  Result:=GetGUIDTaskName;
end;

procedure TgFileTaskWorkerThread.BeforeStart;
begin
  inherited BeforeStart;
  FSpoolDir := IncludeTrailingPathDelimiter(IncludeTrailingPathDelimiter(FRootPoolDir)+FPoolSubDir);
  FProcessedDir := FSpoolDir + 'processed'+DirectorySeparator;
  FErrorDir := FSpoolDir + 'error'+DirectorySeparator;
  EnsureDirsExist;
  if FLoadTasksOnStart then
    LoadAllTasks;
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
  aTaskName: TTaskName;
begin
  aStreamer:=TJSONStreamer.Create(nil);
  try
    try
      aTaskName:=GetTaskName(aTask);
      if not SaveJSONToFile(aStreamer.ObjectToJSONString(aTask), aTaskName) then
        Logger.Error('Can''t save task file %s', [aTaskName]);
    except
      on E: Exception do
        Logger.Error('SaveTaksToFile, task streaming & saving. %s: %s', [E.ClassName, E.Message]);
    end;
  finally
    aStreamer.Free;
  end;
end;

end.

