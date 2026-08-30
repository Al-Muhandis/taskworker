# TaskWorker Library

**Task Worker Thread Template** — A generic, reusable Pascal library for multi-threaded task processing with file-based and in-memory backends.

## Overview

TaskWorker provides a framework for implementing worker threads that process tasks asynchronously. It includes:

- **TgTaskWorkerThread<T>** — Generic base class for task processing threads
- **TgFileTaskWorkerThread<T>** — File-based task queue with automatic JSON serialization
- **TThreadedEventLog** — Asynchronous event logging

The library is designed for long-running services, batch processors, and event-driven applications.

## Installation

Add these units to your project:
- `taskworker.pas` — Core worker thread
- `filetaskworker.pas` — File-based task queue (optional)
- `logworker.pas` — Threaded logging (optional)

Dependencies: FPC 3.0+, fpjson (for file tasks)

## Quick Start

### Basic Task Worker

```pascal
uses taskworker;

type
  TMyTask = class
  public
    Data: String;
  end;

  TMyWorker = class(specialize TgTaskWorkerThread<TMyTask>)
  protected
    procedure ProcessTask(ATask: TMyTask); override;
  end;

procedure TMyWorker.ProcessTask(ATask: TMyTask);
begin
  Logger.Info('Processing: ' + ATask.Data);
  // Your business logic here
  ATask.Free;
end;

// Usage
var Worker: TMyWorker;
begin
  Worker := TMyWorker.Create;
  Worker.Start;
  
  Worker.PushTask(TMyTask.Create);
  // Tasks processed asynchronously in background
  
  Worker.TerminateWorker;
  Worker.WaitFor;
  Worker.Free;
end;
```

### File-Based Task Queue

```pascal
uses filetaskworker;

type
  TTaskData = class
  public
    ID: Integer;
    Name: String;
  end;

  TFileWorker = class(specialize TgFileTaskWorkerThread<TTaskData>)
  protected
    procedure DoProcessTask(aTask: TTaskData; out aIsOk: Boolean); override;
  end;

procedure TFileWorker.DoProcessTask(aTask: TTaskData; out aIsOk: Boolean);
begin
  try
    aIsOk := False;
    Logger.Info('Task %d: %s', [aTask.ID, aTask.Name]);
    // Process...
    aIsOk := True;
  except
    on E: Exception do
      Logger.Error('Error: %s', [E.Message]);
  end;
end;

// Usage
var Worker: TFileWorker;
begin
  Worker := TFileWorker.Create;
  Worker.RootPoolDir := '/var/spool/';
  Worker.PoolSubDir := 'myapp';
  Worker.LoadTasksOnStart := True;
  Worker.Start;
  
  Worker.SendTask(TTaskData.Create);
  // Tasks persisted to disk, survives app restart
end;
```

### Asynchronous Logging

```pascal
uses logworker;

var Log: TThreadedEventLog;
begin
  Log := TThreadedEventLog.Create;
  Log.FileName := 'app.log';
  Log.LogLevel := llInfo;
  Log.Activate;
  
  Log.Info('Application started');
  Log.Warning('Low memory');
  Log.Error('Connection failed: %s', ['timeout']);
  
  Log.Free;
end;
```

## API Reference

### TgTaskWorkerThread<T>

Generic base class for worker threads. Type parameter T must be a TObject descendant.

**Constructor**
```pascal
constructor Create; virtual;
```

**Methods**
- `procedure PushTask(ATask: T)` — Queue a task for processing
- `procedure TerminateWorker` — Signal thread to stop
- `procedure Execute; override` — Main thread loop (do not call)

**Virtual Methods (Override in descendants)**
- `procedure BeforeStart; virtual` — Called once at thread startup
- `procedure ProcessTask(ATask: T); virtual; abstract` — Process one task
- `procedure DoIdle; virtual` — Called when waiting for tasks

**Properties**
- `Count: Integer` — Number of queued tasks
- `Logger: TEventLog` — Built-in event logger
- `OnIdle: TNotifyEvent` — Event fired when idle

### TgFileTaskWorkerThread<T>

File-based task queue with JSON persistence. Extends TgTaskWorkerThread.

**Constructor**
```pascal
constructor Create; override;
```

**Methods**
- `procedure SendTask(aTask: TTask)` — Serialize task to JSON and queue it
- `procedure DoProcessTask(aTask: TTask; out aIsOk: Boolean); virtual` — Override to process tasks
- `function GetTaskName(aTask: TTask): TTaskName; virtual` — Generate task filename

**Properties**
- `RootPoolDir: String` — Base spool directory (default: platform-specific)
- `PoolSubDir: String` — Subdirectory name (default: 'tasks')
- `LoadTasksOnStart: Boolean` — Reload unprocessed tasks on startup
- `DeleteProcessed: Boolean` — Delete processed files after completion

**Directory Structure**
```
RootPoolDir/PoolSubDir/
  *.json                 (unprocessed tasks)
  processed/             (successfully processed)
  error/                 (failed tasks)
```

### TThreadedEventLog

Asynchronous file-based logging.

**Constructor**
```pascal
constructor Create;
```

**Methods**
- `procedure Activate` — Start logging thread
- `procedure Debug(const Msg: String)` — Log debug message
- `procedure Info(const Msg: String)` — Log info message
- `procedure Warning(const Msg: String)` — Log warning message
- `procedure Error(const Msg: String)` — Log error message
- `procedure Log(EventType: TEventType; const Msg: String)` — Log with explicit level

All methods support format string variants: `Debug(Format: String; Args: array of const)`

**Properties**
- `FileName: String` — Output log file path
- `LogLevel: TLogLevel` — Minimum level to log (llDebug, llInfo, llWarning, llError, llNone)
- `AppendContent: Boolean` — Append to file (default: False)
- `Paused: Boolean` — Temporarily suppress logging
- `Active: Boolean` — Thread is running (read-only)

**Helper Functions**
- `function LogLevelToString(Level: TLogLevel): String`
- `function StringToLogLevel(const S: String): TLogLevel`

## Use Cases

**TgTaskWorkerThread<T>** — In-memory queue:
- Real-time event processing
- Background computations
- Parallel task execution

**TgFileTaskWorkerThread<T>** — Persistent queue:
- Long-running batch jobs
- Task recovery after restart
- Audit trail of processed/failed tasks

**TThreadedEventLog** — Non-blocking logging:
- High-frequency logging
- Won't slow down main thread
- Configurable severity levels

## Best Practices

1. **Always shutdown cleanly:**
   ```pascal
   Worker.TerminateWorker;
   Worker.WaitFor;
   Worker.Free;
   ```

2. **Configure before starting:**
   ```pascal
   Worker.RootPoolDir := '/tmp/';
   Worker.Start;
   ```

3. **Handle exceptions in ProcessTask:**
   ```pascal
   procedure ProcessTask(ATask: T); override;
   begin
     try
       // ...
     except
       on E: Exception do
         Logger.Error('Error: %s', [E.Message]);
     end;
   end;
   ```

4. **Set log file before using:**
   ```pascal
   Log.FileName := 'app.log';
   Log.Info('First message');
   ```

## Platform Support

- Windows, Linux, macOS, FreeBSD
- FPC 3.0+
- Requires: Classes, SysUtils, eventlog
- File tasks also require: fpjson, jsonparser, fpjsonrtti

## License

MIT License

## See Also

- Source code: `taskworker.pas`, `filetaskworker.pas`, `logworker.pas`
- Repository: https://github.com/Al-Muhandis/taskworker
