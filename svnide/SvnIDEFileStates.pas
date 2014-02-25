{******************************************************************************}
{                                                                              }
{ RAD Studio Version Insight                                                   }
{                                                                              }
{ The contents of this file are subject to the Mozilla Public License          }
{ Version 1.1 (the "License"); you may not use this file except in compliance  }
{ with the License. You may obtain a copy of the License at                    }
{ http://www.mozilla.org/MPL/                                                  }
{                                                                              }
{ Software distributed under the License is distributed on an "AS IS" basis,   }
{ WITHOUT WARRANTY OF ANY KIND, either express or implied. See the License for }
{ the specific language governing rights and limitations under the License.    }
{                                                                              }
{ The Original Code is SvnIDEFileStates.pas.                                   }
{                                                                              }
{ The Initial Developer of the Original Code is Uwe Schuster.                  }
{ Portions created by Uwe Schuster are Copyright � 2010 - 2014 Uwe Schuster.   }
{ All Rights Reserved.                                                         }
{                                                                              }
{ Contributors:                                                                }
{ Uwe Schuster (uschuster)                                                     }
{                                                                              }
{******************************************************************************}

unit SvnIDEFileStates;

interface

uses
  Classes;

procedure FlushFileListFileStates(AFileList: TStringList);
procedure FlushFileState(const AFileName: string);
function GetFileStateProvider: IInterface;
procedure RegisterFileStateProvider;
procedure UnregisterFileStateProvider;

implementation

{$IFDEF TOOLSPROAPI}
uses
  SyncObjs, SysUtils, Graphics, Generics.Collections, ToolsAPI, DesignIntf, ToolsProAPI, svn_client, SvnClient,
  SvnIDEClient, TypInfo;

type
  TOnStateEvent = procedure(const AFileName: string; AVersioned: Boolean; ATextStatus: TSvnWCStatusKind; AProperties: TStringList) of object;

  TSvnStateThread = class(TThread)
  private
    FSvnClient: TSvnClient;
    FItems: TStringList;
    FLock: TCriticalSection;
    FOnState: TOnStateEvent;
    procedure DoState(const AFileName: string; AVersioned: Boolean; ATextStatus: TSvnWCStatusKind; AProperties: TStringList);
  protected
    procedure Execute; override;
  public
    constructor Create(CreateSuspended: Boolean);
    destructor Destroy; override;
    procedure AddItem(const AFileName: string);
    property OnState: TOnStateEvent read FOnState write FOnState;
  end;

  TSvnRetrievalState = (rsNew, rsRunning, rsFinished);

  TSvnState = class(TObject)
  private
    FFileName: string;
    FProperties: TStringList;
    FRetrievalState: TSvnRetrievalState;
    FState: TOTAProFileState;
  public
    constructor Create(const AFileName: string; AState: TOTAProFileState);
    destructor Destroy; override;
    property FileName: string read FFileName;
    property Properties: TStringList read FProperties;
    property RetrievalState: TSvnRetrievalState read FRetrievalState write FRetrievalState;
    property State: TOTAProFileState read FState write FState;
  end;

  TSvnStateDir = class(TObject)
  private
    FDirectory: string;
    FItems: TObjectDictionary<string, TSvnState>;
  public
    constructor Create(ADirectory: string);
    destructor Destroy; override;
    procedure DeleteFile(const FileName: string);
    function GetState(const AFileName: string): TSvnState;
    property Directory: string read FDirectory;
  end;

  TSvnStateDirList = class(TObject)
  private
    FItems: TObjectDictionary<string, TSvnStateDir>;
  public
    constructor Create;
    destructor Destroy; override;
    procedure Clear;
    procedure DeleteDirectory(const ADirectory: string);
    procedure DeleteFile(const FileName: string);
    function GetDirectory(const ADirectory: string): TSvnStateDir;
  end;

  TIOTAProVersionControlFileStateProvider = class(TInterfacedObject,
    IOTAProVersionControlFileStateProvider)
  private
    class var
      FSingleton: TIOTAProVersionControlFileStateProvider;
    var
    FThread: TSvnStateThread;
    FItems: TSvnStateDirList;
    FLock: TCriticalSection;
    FRestartThread: Boolean;
    FUpdateCount: Integer;
    procedure HandleState(const AFileName: string; AVersioned: Boolean; ATextStatus: TSvnWCStatusKind; AProperties: TStringList);
  protected
    procedure AfterCOmpile;
    procedure AfterCloseAll;
    procedure BeforeCOmpile;
    procedure FlushDir(const ADirectory: string);
    procedure FlushFile(const FileName: string);
    function GetCommonFileState(const FileName: string; AChildFiles: TStrings;
      var AFileState: TOTAProFileState): TOTAProFileStateResult;
    function GetFileState(const FileName: string; var AFileState: TOTAProFileState): TOTAProFileStateResult;
    function GetFileStateInfo(const FileName: string; var AProperty: IProperty): TOTAProFileStateResult;
  public
    constructor Create;
    destructor Destroy; override;
    class procedure FlushFiles(AFileList: TStringList);
  end;

constructor TSvnStateThread.Create(CreateSuspended: Boolean);
begin
  FSvnClient := IDEClient.SvnClient;
  FLock := TCriticalSection.Create;
  FItems := TStringList.Create;
  FItems.Sorted := True;
  inherited Create(CreateSuspended);
end;

destructor TSvnStateThread.Destroy;
begin
  inherited Destroy;
  FItems.Free;
  FLock.Free;
end;

procedure TSvnStateThread.AddItem(const AFileName: string);
begin
  FLock.Enter;
  try
    if FItems.IndexOf(AFileName) = -1 then
      FItems.Add(AFileName);
  finally
    FLock.Leave;
  end;
end;

procedure TSvnStateThread.DoState(const AFileName: string; AVersioned: Boolean; ATextStatus: TSvnWCStatusKind;
  AProperties: TStringList);
begin
  if Assigned(FOnState) then
    FOnState(AFileName, AVersioned, ATextStatus, AProperties);
end;

procedure TSvnStateThread.Execute;
var
  FileName: string;
  TextStatus: TSvnWCStatusKind;
  SvnItem: TSvnItem;
  Locked: Boolean;
  Properties: TStringList;
  FileDir, LastDirectory: string;
  LastDirectoryVersioned: Boolean;
begin
  NameThreadForDebugging('DelphiSVN State Retriever');
  LastDirectoryVersioned := False;
  while not Terminated do
  begin
    FileName := '';
    Locked := FLock.TryEnter;
    try
      if Locked and (FItems.Count > 0) then
      begin
        FileName := FItems[0];
        FItems.Delete(0);
      end
      else
        LastDirectory := '';
    finally
      if Locked then
        FLock.Leave;
    end;
    if FileName <> '' then
    begin
      try
        FileDir := ExtractFilePath(FileName);
        if not AnsiSameText(LastDirectory, FileDir) then
        begin
          LastDirectory := FileDir;
          LastDirectoryVersioned := FSvnClient.IsPathVersioned(FileDir);
        end;
        if LastDirectoryVersioned then
        begin
          Properties := TStringList.Create;
          try
            SvnItem := TSvnItem.Create(FSvnClient, nil, FileName, False, False, True);
            try
              TextStatus := SvnItem.TextStatus;
              //TODO: Resourcestrings
              Properties.Add('URL='+ SvnItem.URL);
              Properties.Add('Repository=' + SvnItem.Repository);
              Properties.Add('Text Status=' + StatusKindStr(SvnItem.TextStatus));
              Properties.Add('Property Status=' + StatusKindStr(SvnItem.PropStatus));
              if not (TextStatus in [svnWcStatusAdded]) then
              begin
                Properties.Add('Base Revision=' + IntToStr(SvnItem.BaseRevision));
                Properties.Add('Committed Revision=' + IntToStr(SvnItem.CommittedRevision));
                Properties.Add('Committed Author=' + SvnItem.CommitAuthor);
                Properties.Add('Commit Time=' + DateTimeToStr(SvnItem.CommitTime));
              end;
            finally
              SvnItem.Free;
            end;
            DoState(FileName, True, TextStatus, Properties);
          finally
            Properties.Free;
          end;
        end
        else
          DoState(FileName, False, svnWcStatusNone, nil);
      except
      end;
    end;
    Sleep(1);
  end;
end;

constructor TSvnState.Create(const AFileName: string; AState: TOTAProFileState);
begin
  inherited Create;
  FFileName := AFileName;
  FProperties := TStringList.Create;
  FRetrievalState := rsNew;
  FState := AState;
end;

destructor TSvnState.Destroy;
begin
  FProperties.Free;
  inherited Destroy;
end;

constructor TSvnStateDir.Create(ADirectory: string);
begin
  inherited Create;
  FDirectory := ADirectory;
  FItems := TObjectDictionary<string, TSvnState>.Create([doOwnsValues]);
end;

destructor TSvnStateDir.Destroy;
begin
  FItems.Free;
  inherited Destroy;
end;

procedure TSvnStateDir.DeleteFile(const FileName: string);
begin
  FItems.Remove(AnsiLowerCase(FileName));
end;

function TSvnStateDir.GetState(const AFileName: string): TSvnState;
var
  State: TOTAProFileState;
  LowerCaseFileName: string;
begin
  LowerCaseFileName := AnsiLowerCase(AFileName);
  if not FItems.TryGetValue(LowerCaseFileName, Result) then
  begin
    State.OverlayImageIndex := -1;
    State.StatusBarImageIndex := -1;
    State.DisplayText := '?';
    State.TextColor := clNone;
    FItems.Add(LowerCaseFileName, TSvnState.Create(AFileName, State));
    if not FItems.TryGetValue(LowerCaseFileName, Result) then
      Result := nil;
  end;
end;

constructor TSvnStateDirList.Create;
begin
  inherited Create;
  FItems := TObjectDictionary<string, TSvnStateDir>.Create([doOwnsValues]);
end;

procedure TSvnStateDirList.Clear;
begin
  FItems.Clear;
end;

procedure TSvnStateDirList.DeleteDirectory(const ADirectory: string);
begin
  FItems.Remove(AnsiLowerCase(ADirectory));
end;

procedure TSvnStateDirList.DeleteFile(const FileName: string);
var
  Dir: TSvnStateDir;
begin
  if FItems.TryGetValue(AnsiLowerCase(ExtractFilePath(FileName)), Dir) then
    Dir.DeleteFile(FileName);
end;

destructor TSvnStateDirList.Destroy;
begin
  FItems.Free;
  inherited Destroy;
end;

function TSvnStateDirList.GetDirectory(const ADirectory: string): TSvnStateDir;
var
  LowerCaseDirName: string;
begin
  LowerCaseDirName := AnsiLowerCase(ADirectory);
  if not FItems.TryGetValue(LowerCaseDirName, Result) then
  begin
    FItems.Add(LowerCaseDirName, TSvnStateDir.Create(ADirectory));
    if not FItems.TryGetValue(LowerCaseDirName, Result) then
      Result := nil;
  end;
end;

{ TIOTAProVersionControlFileStateProvider }

constructor TIOTAProVersionControlFileStateProvider.Create;
begin
  inherited Create;
  FThread := TSvnStateThread.Create(True);
  FThread.OnState := HandleState;
  FItems := TSvnStateDirList.Create;
  FLock := TCriticalSection.Create;
  FRestartThread := False;
  FUpdateCount := 0;
  if not Assigned(FSingleton) then
    FSingleton := Self
  else
    raise Exception.CreateFmt('There must not be multiple instances of %s.', [ClassName]);
end;

destructor TIOTAProVersionControlFileStateProvider.Destroy;
begin
  if FSingleton = Self then
    FSingleton := nil;
  FLock.Free;
  FItems.Free;
  if not FThread.Suspended then
  begin
    FThread.Terminate;
    FThread.WaitFor;
  end;
  FThread.Free;
  inherited Destroy;
end;

procedure TIOTAProVersionControlFileStateProvider.AfterCloseAll;
begin
  if IDEClient.Options.ClearFileStatesAfterCloseAll then
  begin
    FLock.Enter;
    try
      FItems.Clear;
    finally
      FLock.Leave;
    end;
  end;
end;

procedure TIOTAProVersionControlFileStateProvider.AfterCompile;
begin
  Dec(FUpdateCount);
  if FUpdateCount <= 0 then
  begin
    FUpdateCount := 0;
    if FRestartThread then
    begin
      FThread.Resume;
      FRestartThread := False;
    end;
  end;
end;

procedure TIOTAProVersionControlFileStateProvider.BeforeCompile;
begin
  Inc(FUpdateCount);
  if not FThread.Suspended then
    FThread.Suspend;
end;

procedure TIOTAProVersionControlFileStateProvider.FlushDir(const ADirectory: string);
begin
  FLock.Enter;
  try
    FItems.DeleteDirectory(ADirectory);
  finally
    FLock.Leave;
  end;
end;

procedure TIOTAProVersionControlFileStateProvider.FlushFile(const FileName: string);
begin
  FLock.Enter;
  try
    FItems.DeleteFile(FileName);
  finally
    FLock.Leave;
  end;
end;

class procedure TIOTAProVersionControlFileStateProvider.FlushFiles(AFileList: TStringList);
var
  I: Integer;
begin
  if Assigned(FSingleton) then
    for I := 0 to AFileList.Count - 1 do
      FSingleton.FlushFile(AFileList[I]);
end;

function TIOTAProVersionControlFileStateProvider.GetCommonFileState(
  const FileName: string; AChildFiles: TStrings;
  var AFileState: TOTAProFileState): TOTAProFileStateResult;
var
  I: Integer;
  Deferred, Modified: Boolean;
  CurrentResult: TOTAProFileStateResult;
  CurrentState: TOTAProFileState;
  States: TList<TOTAProFileState>;
begin
  CurrentResult := GetFileState(FileName, CurrentState);
  if CurrentResult in [fsrError, fsrDeferred] then
    Result := CurrentResult
  else
  if CurrentState.FileStateIndex <> fsiNormal then
  begin
    Result := CurrentResult;
    AFileState := CurrentState;
  end
  else
  begin
    States := TList<TOTAProFileState>.Create;
    try
      States.Add(CurrentState);
      Deferred := False;
      for I := 0 to AChildFiles.Count - 1 do
      begin
        CurrentResult := GetFileState(AChildFiles[I], CurrentState);
        if CurrentResult = fsrOK then
          States.Add(CurrentState)
        else
        if CurrentResult = fsrDeferred then
        begin
          Deferred := True;
          Break;
        end;
      end;
      if Deferred then
        Result := fsrDeferred
      else
      begin
        Modified := False;
        for I := 0 to States.Count - 1 do
          if not (States[I].FileStateIndex in [fsiNormal, fsiReadOnly, fsiLocked, fsiIgnored, fsiNonVersioned]) then
          begin
            Modified := True;
            Break;
          end;
        if Modified then
          (BorlandIDEServices as IOTAProVersionControlServices).GetDefaultFileStateValues(fsiModified, AFileState)
        else
          AFileState := States[0];
        Result := fsrOK;
      end;
    finally
      States.Free;
    end;
  end;
end;

function TIOTAProVersionControlFileStateProvider.GetFileState(const FileName: string;
  var AFileState: TOTAProFileState): TOTAProFileStateResult;
var
  StateDir: TSvnStateDir;
  StartThread: Boolean;
  State: TSvnState;
begin
  Result := fsrError;
  FLock.Enter;
  try
    StateDir := FItems.GetDirectory(ExtractFilePath(FileName));
    if Assigned(StateDir) then
    begin
      State := StateDir.GetState(FileName);
      AFileState := State.State;
      if State.RetrievalState in [rsNew, rsRunning] then
        Result := fsrDeferred
      else
      if AFileState.DisplayText <> '?' then
        Result := fsrOK;
    end;
    StartThread := False;
    if (State.RetrievalState = rsNew) and (Result = fsrDeferred) then
    begin
      FThread.AddItem(FileName);
      State.RetrievalState := rsRunning;
      StartThread := True;
    end;
  finally
    FLock.Leave;
  end;
  if StartThread and FThread.Suspended then
  begin
    if FUpdateCount = 0 then
      FThread.Resume
    else
      FRestartThread := True;
  end;
end;

type
  TSimpleStringProperty = class(TInterfacedObject, IProperty, IPropertyDescription, IPropertyKind)
  private
    FDescription: string;
    FName: string;
    FValue: string;
    FHasSub: Boolean;
    FReadOnly: Boolean;
    FSubproperties: TStringList;
  protected
    { IPropertyDescription }
    function GetDescription: string;
    { IProperty }
    procedure Activate;
    function AllEqual: Boolean;
    function AutoFill: Boolean;
    procedure Edit; overload;
    function HasInstance(Instance: TPersistent): Boolean;
    function GetAttributes: TPropertyAttributes;
    function GetEditLimit: Integer;
    function GetEditValue(out Value: string): Boolean;
    function GetName: string;
    procedure GetProperties(Proc: TGetPropProc);
    function GetPropInfo: PPropInfo;
    function GetPropType: PTypeInfo;
    function GetValue: string;
    procedure GetValues(Proc: TGetStrProc);
    procedure Revert;
    procedure SetValue(const Value: string);
    function ValueAvailable: Boolean;
    { IPropertyKind }
    function GetKind: TTypeKind;
    property Kind: TTypeKind read GetKind;
  public
    constructor Create(const AName, ADescription, AValue: string; AReadOnly: Boolean = True; ASubItems: TStringList = nil);
    destructor Destroy; override;
    property HasSub: Boolean read FHasSub;
  end;

constructor TSimpleStringProperty.Create(const AName, ADescription, AValue: string; AReadOnly: Boolean = True; ASubItems: TStringList = nil);
begin
  inherited Create;
  FDescription := ADescription;
  FName := AName;
  FValue := AValue;
  FReadOnly := AReadOnly;
  FSubproperties := TStringList.Create;
  if Assigned(ASubItems) then
    FSubproperties.Assign(ASubItems);
end;

destructor TSimpleStringProperty.Destroy;
begin
  FSubproperties.Free;
  inherited Destroy;
end;

procedure TSimpleStringProperty.Activate;
begin
//
end;

function TSimpleStringProperty.AllEqual: Boolean;
begin
  Result := True;
end;

function TSimpleStringProperty.AutoFill: Boolean;
begin
  Result := False;
end;

procedure TSimpleStringProperty.Edit;
begin
//
end;

function TSimpleStringProperty.GetAttributes: TPropertyAttributes;
begin
  Result := [paReadOnly];
  if FReadOnly then
  begin
    Include(Result, paDisplayReadOnly);
  end;
  if FSubproperties.Count > 0 then
    Include(Result, paSubProperties);
end;

function TSimpleStringProperty.GetDescription: string;
begin
  Result := FDescription;
end;

function TSimpleStringProperty.GetEditLimit: Integer;
begin
  Result := 255;
end;

function TSimpleStringProperty.GetEditValue(out Value: string): Boolean;
begin
  Result := False;
  Value := GetValue;
end;

function TSimpleStringProperty.GetKind: TTypeKind;
begin
  Result := tkString;
end;

function TSimpleStringProperty.GetName: string;
begin
  Result := FName;
end;

procedure TSimpleStringProperty.GetProperties(Proc: TGetPropProc);
var
  I: Integer;
  S, S2: string;
begin
  for I := 0 to FSubproperties.Count - 1 do
  begin
    S := FSubproperties.Names[I];
    S2 := FSubproperties.ValueFromIndex[I];
    Proc(TSimpleStringProperty.Create(S, '', S2));
  end;
end;

function TSimpleStringProperty.GetPropInfo: PPropInfo;
begin
  Result := nil;
end;

function TSimpleStringProperty.GetPropType: PTypeInfo;
begin
  Result := nil;
end;

function TSimpleStringProperty.GetValue: string;
begin
  Result := FValue;
end;

procedure TSimpleStringProperty.GetValues(Proc: TGetStrProc);
begin
//
end;

function TSimpleStringProperty.HasInstance(Instance: TPersistent): Boolean;
begin
  Result := False;
end;

procedure TSimpleStringProperty.Revert;
begin
//
end;

procedure TSimpleStringProperty.SetValue(const Value: string);
begin
//
end;

function TSimpleStringProperty.ValueAvailable: Boolean;
begin
  Result := True;
end;

function TIOTAProVersionControlFileStateProvider.GetFileStateInfo(const FileName: string;
  var AProperty: IProperty): TOTAProFileStateResult;
var
  StateDir: TSvnStateDir;
  StartThread: Boolean;
  State: TSvnState;
begin
  Result := fsrError;
  FLock.Enter;
  try
    StateDir := FItems.GetDirectory(ExtractFilePath(FileName));
    if Assigned(StateDir) then
    begin
      State := StateDir.GetState(FileName);
      if State.RetrievalState in [rsNew, rsRunning] then
        Result := fsrDeferred
      else
      if State.State.DisplayText <> '?' then
        Result := fsrOK;
    end
    else
      State := nil;
    StartThread := False;
    if (State.RetrievalState = rsNew) and (Result = fsrDeferred) then
    begin
      FThread.AddItem(FileName);
      State.RetrievalState := rsRunning;
      StartThread := True;
    end;
    if Result = fsrOK then //TODO: Resourcestring
      AProperty := TSimpleStringProperty.Create('Subversion Status', 'Subversion Status', '', True, State.Properties);
  finally
    FLock.Leave;
  end;
  if StartThread and FThread.Suspended then
  begin
    if FUpdateCount = 0 then
      FThread.Resume
    else
      FRestartThread := True;
  end;
end;

procedure TIOTAProVersionControlFileStateProvider.HandleState(
  const AFileName: string; AVersioned: Boolean; ATextStatus: TSvnWCStatusKind;
  AProperties: TStringList);
var
  StateDir: TSvnStateDir;
  State: TSvnState;
  StateVar: TOTAProFileState;
  Idx: Integer;
begin
  FLock.Enter;
  try
    StateDir := FItems.GetDirectory(ExtractFilePath(AFileName));
    if Assigned(StateDir) then
    begin
      State := StateDir.GetState(AFileName);
      State.RetrievalState := rsFinished;
      if AVersioned then
      begin
        case ATextStatus of
          svnWcStatusNormal: Idx := fsiNormal;
          svnWcStatusModified: Idx := fsiModified;
          svnWcStatusConflicted: Idx := fsiConflicted;
          svnWcStatusDeleted: Idx := fsiDeleted;
          svnWcStatusAdded: Idx :=  fsiAdded;
          svnWcStatusIgnored: Idx := fsiIgnored;
          svnWcStatusUnversioned: Idx := fsiNonVersioned;
          else
            Idx := -1;
        end;
      end
      else
        Idx := -1;
      if not (BorlandIDEServices as IOTAProVersionControlServices).GetDefaultFileStateValues(Idx, StateVar) then
      begin
        StateVar.OverlayImageIndex := -1;
        StateVar.StatusBarImageIndex := -1;
        StateVar.DisplayText := '?';
        StateVar.TextColor := clNone;
      end;
      State.State := StateVar;
      if Assigned(AProperties) then
        State.Properties.Assign(AProperties)
      else
        State.Properties.Clear;
    end;
  finally
    FLock.Leave;
  end;
  (BorlandIDEServices as IOTAProVersionControlServices).InvalidateControls;
end;

var
  NotifierIndex: Integer = -1;

procedure FlushFileListFileStates(AFileList: TStringList);
begin
  TIOTAProVersionControlFileStateProvider.FlushFiles(AFileList);
  if Supports(BorlandIDEServices, IOTAProVersionControlServices) then
    (BorlandIDEServices as IOTAProVersionControlServices).InvalidateControls;
end;

procedure FlushFileState(const AFileName: string);
var
  SL: TStringList;
begin
  SL := TStringList.Create;
  try
    SL.Add(AFileName);
    FlushFileListFileStates(SL);
  finally
    SL.Free;
  end;
end;

function GetFileStateProvider: IInterface;
begin
  Result := TIOTAProVersionControlFileStateProvider.FSingleton;
end;

procedure RegisterFileStateProvider;
begin
  if Supports(BorlandIDEServices, IOTAProVersionControlServices) then
    NotifierIndex := (BorlandIDEServices as IOTAProVersionControlServices).RegisterFileStateProvider(TIOTAProVersionControlFileStateProvider.Create);
end;

procedure UnregisterFileStateProvider;
begin
  if NotifierIndex <> -1 then
  begin
    if Supports(BorlandIDEServices, IOTAProVersionControlServices) then
      (BorlandIDEServices as IOTAProVersionControlServices).UnregisterFileStateProvider(NotifierIndex);
    NotifierIndex := -1;
  end;
end;

{$ELSE ~TOOLSPROAPI}
procedure FlushFileListFileStates(AFileList: TStringList);
begin
//
end;

procedure FlushFileState(const AFileName: string);
begin
//
end;

function GetFileStateProvider: IInterface;
begin
  Result := nil;
end;

procedure RegisterFileStateProvider;
begin
//
end;

procedure UnregisterFileStateProvider;
begin
//
end;
{$ENDIF TOOLSPROAPI}

initialization

finalization
  UnregisterFileStateProvider;

end.
