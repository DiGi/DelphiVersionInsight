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
{ The Original Code is delphisvn: Subversion plugin for CodeGear Delphi.       }
{                                                                              }
{ The Initial Developer of the Original Code is Embarcadero Technologies.      }
{ Portions created by Ondrej Kelle are Copyright Ondrej Kelle. All rights      }
{ reserved.                                                                    }
{                                                                              }
{ Portions created or modified by Embarcadero Technologies are                 }
{ Copyright � 2010 Embarcadero Technologies, Inc. All Rights Reserved          }
{ Modifications include a major re-write of delphisvn. New functionality for   }
{ diffing, international character support, asynchronous gathering of data,    }
{ check-out and import, usability, tighter integration into RAD Studio, and    }
{ other new features.  Most original source files not used or re-written.      }
{                                                                              }
{ Contributors:                                                                }
{ Ondrej Kelle (tondrej)                                                       }
{ Uwe Schuster (uschuster)                                                     }
{ Embarcadero Technologies                                                     }
{                                                                              }
{******************************************************************************}
unit HgIDELog;

interface

uses Classes, HgIDEMenus, HgIDEClient;

type
  TBaseLogHgMenu = class(THgMenu)
  protected
    FRootType: TRootType;
    FHgIDEClient: THgIDEClient;
    procedure Execute(const MenuContextList: IInterfaceList); override;
  public
    constructor Create(AHgIDEClient: THgIDEClient);
  end;

  TParentLogHgMenu = class(THgMenu)
  protected
    function GetImageIndex: Integer; override;
  public
    constructor Create;
  end;

  TRootDirLogHgMenu = class(TBaseLogHgMenu)
  public
    constructor Create(AHgIDEClient: THgIDEClient);
  end;

  TProjectDirLogHgMenu = class(TBaseLogHgMenu)
  public
    constructor Create(AHgIDEClient: THgIDEClient);
  end;

  TDirLogHgMenu = class(TBaseLogHgMenu)
  protected
    function GetImageIndex: Integer; override;
  public
    constructor Create(AHgIDEClient: THgIDEClient);
  end;

 procedure Register;

implementation

uses SysUtils, HgIDEConst, ToolsApi, HgClientLog, HgClient, DesignIntf, Forms,
  HgUITypes, HgIDEUtils, ExtCtrls, Graphics, HgIDETypes, RegularExpressions,
  HgIDEIcons;

const
  sPMVLogParent = 'SvnLogParent';
  sLogView = 'LogViewHg';
  sPMVRootDirLog = 'RootDirLog';
  sPMVProjectDirLog = 'ProjectDirLog';
  sPMVExpicitFilesLog = 'ExpicitFilesLog';
  sPMVDirLog = 'DirLog';

var
  LogView: INTACustomEditorView;

type
  TLogView = class(TInterfacedObject, INTACustomEditorView,
    INTACustomEditorView150, IHgAsyncUpdate)
  protected
    var
      FHgClient: THgClient;
      FSvnLogFrame: THgLogFrame;
      FHgItem: THgItem;
      FRootPath: string;
      FFirst: Integer;
    { INTACustomEditorView }
    function GetCanCloneView: Boolean;
    function CloneEditorView: INTACustomEditorView;
    function GetCaption: string;
    function GetEditorWindowCaption: string;
    function GetViewIdentifier: string;
    function GetEditState: TEditState;
    function EditAction(Action: TEditAction): Boolean;
    procedure CloseAllCalled(var ShouldClose: Boolean);
    procedure SelectView;
    procedure DeselectView;
    function GetFrameClass: TCustomFrameClass;
    procedure FrameCreated(AFrame: TCustomFrame);
    { INTACustomEditorView150 }
    function GetImageIndex: Integer;
    function GetTabHintText: string;
    procedure Close(var Allowed: Boolean);
    { AsyncUpdate }
    procedure UpdateHistoryItems(HgItem: THgItem; FirstNewIndex, LastNewIndex: Integer;
      ForceUpdate: Boolean);
    procedure Completed;
    { CallBacks }
    procedure LoadRevisionsCallBack(FirstRevision, LastRevision: Integer; Count: Integer);
    function FileColorCallBack(Action: Char): TColor;
    procedure ReverseMergeCallBack(const APathName: string; ARevision1, ARevision2: Integer);
    procedure CompareRevisionCallBack(AFileList: TStringList; ARevision1, ARevision2: Integer);
    procedure SaveRevisionCallBack(AFileList: TStringList; ARevision: Integer; const ADestPath: string);
  public
    constructor Create(HgClient: THgClient; const ARootPath: string);
    destructor Destroy; override;
  end;

{ TBaseLogSvnMenu }

constructor TBaseLogHgMenu.Create(AHgIDEClient: THgIDEClient);
begin
  inherited;
  FParent := sPMVLogParent;
  FHgIDEClient := AHgIDEClient;
end;

procedure TBaseLogHgMenu.Execute(const MenuContextList: IInterfaceList);
var
  RootPath: string;
  MenuContext: IOTAMenuContext;
begin
  if Supports(MenuContextList[0], IOTAMenuContext, MenuContext) then
  begin
    if FRootType = rtRootDir then
      RootPath := RootDirectory(FHgIDEClient.HgClient, MenuContext.Ident)
    else
    if FRootType = rtProjectDir then
      RootPath := ExtractFilePath(MenuContext.Ident)
    else
    if FRootType = rtDir then
      RootPath := IncludeTrailingPathDelimiter(MenuContext.Ident)
    else
      RootPath := '';
    //TODO: check if path is not empty and is versioned
    //TODO: check if there is already a Log view
    // (otherwise you will currently receive an "A component named SvnLogFrame already exists." exception)
    LogView := TLogView.Create(FHgIDEClient.HgClient, RootPath);
    (BorlandIDEServices as IOTAEditorViewServices).ShowEditorView(LogView);
  end;
end;

{ TParentLogSvnMenu }

constructor TParentLogHgMenu.Create;
begin
  inherited Create(nil);
  FCaption := sPMMLog;
  FVerb := sPMVLogParent;
  FParent := sPMVHgParent;
  FPosition := pmmpParentLogSvnMenu;
  FHelpContext := 0;
end;

{ TRootDirLogSvnMenu }

constructor TRootDirLogHgMenu.Create(AHgIDEClient: THgIDEClient);
begin
  inherited Create(AHgIDEClient);
  FRootType := rtRootDir;
  FCaption := sPMMRootDir;
  FVerb := sPMVRootDirLog;
  FPosition := pmmpRootDirLogSvnMenu;
  FHelpContext := 0;
end;

{ TProjectDirLogSvnMenu }

constructor TProjectDirLogHgMenu.Create(AHgIDEClient: THgIDEClient);
begin
  inherited Create(AHgIDEClient);
  FRootType := rtProjectDir;
  FCaption := sPMMProjectDir;
  FVerb := sPMVProjectDirLog;
  FPosition := pmmpProjectDirLogSvnMenu;
  FHelpContext := 0;
end;

{ TDirLogHgMenu }

constructor TDirLogHgMenu.Create(AHgIDEClient: THgIDEClient);
begin
  inherited Create(AHgIDEClient);
  FRootType := rtDir;
  FParent := sPMVHgParent;
  FCaption := sPMMLog;
  FVerb := sPMVDirLog;
  FPosition := pmmpProjectDirLogSvnMenu;
  FHelpContext := 0;
end;

function TDirLogHgMenu.GetImageIndex: Integer;
begin
  Result := LogImageIndex;
end;

{ TLogView }

function TLogView.CloneEditorView: INTACustomEditorView;
begin
  Result := nil;
end;

procedure TLogView.Close(var Allowed: Boolean);
begin

end;

procedure TLogView.CloseAllCalled(var ShouldClose: Boolean);
begin
  ShouldClose := True;
end;

procedure TLogView.CompareRevisionCallBack(AFileList: TStringList; ARevision1,
  ARevision2: Integer);
var
  I: Integer;
  CompareRevisionThread: TCompareRevisionThread;
  RootPath: string;
begin
  CompareRevisionThread := TCompareRevisionThread.Create;
  RootPath := IDEClient.HgClient.FindRepositoryRoot(FRootPath) + '\'; //TODO:1
  for I := 0 to AFileList.Count - 1 do
    CompareRevisionThread.AddFile(RootPath + AFileList[I], ARevision1, ARevision2);
  CompareRevisionThread.Start;
end;

procedure TLogView.Completed;
begin
  if Assigned(FSvnLogFrame) then
    FSvnLogFrame.NextCompleted;
end;

constructor TLogView.Create(HgClient: THgClient; const ARootPath: string);
begin
  inherited Create;
  FHgClient := HgClient;
  FRootPath := ARootPath;
end;

procedure TLogView.DeselectView;
begin
  // Not used
end;

destructor TLogView.Destroy;
begin
  if FHgItem <> nil then
    FHgItem.Free;
  inherited;
end;

function TLogView.EditAction(Action: TEditAction): Boolean;
var
  SvnEditAction: TSvnEditAction;
begin
  Result := False;
  if Assigned(FSvnLogFrame) then
  begin
    SvnEditAction := EditActionToSvnEditAction(Action);
    if SvnEditAction <> seaUnknown then
      Result := FSvnLogFrame.PerformEditAction(SvnEditAction);
  end;
end;

function TLogView.FileColorCallBack(Action: Char): TColor;
begin
  Result := IDEClient.Colors.GetLogActionColor(Action);
end;

procedure TLogView.FrameCreated(AFrame: TCustomFrame);
var
  RepoRootPath, RootRelativePath: string;
begin
  FSvnLogFrame := THgLogFrame(AFrame);

  FHgItem := THgItem.Create(FHgClient, FRootPath);
  LoadRevisionsCallBack(-1, -1, 100);

  FSvnLogFrame.FileColorCallBack := FileColorCallBack;
  FSvnLogFrame.LoadRevisionsCallBack := LoadRevisionsCallBack;
  //FSvnLogFrame.ReverseMergeCallBack := ReverseMergeCallBack;
  FSvnLogFrame.CompareRevisionCallBack := CompareRevisionCallBack;
  FSvnLogFrame.SaveRevisionCallBack := SaveRevisionCallBack;
  FSvnLogFrame.RootPath := ExcludeTrailingPathDelimiter(FRootPath);
  RepoRootPath := IDEClient.HgClient.FindRepositoryRoot(FRootPath);
  RepoRootPath := IncludeTrailingPathDelimiter(StringReplace(RepoRootPath, '/', '\', [rfReplaceAll]));
  if RepoRootPath <> FRootPath then
  begin
    RootRelativePath := Copy(FRootPath, Length(RepoRootPath) + 1, MaxInt);
    RootRelativePath := StringReplace(RootRelativePath, '\', '/', [rfReplaceAll]);
  end
  else
    RootRelativePath := '';
  FSvnLogFrame.RootRelativePath := RootRelativePath;
  {
  FSvnLogFrame.ShowBugIDColumn := FBugIDParser.BugTraqLogRegEx <> '';
  FSvnItem := TSvnItem.Create(FSvnClient, nil, FRootPath, True);
  FSvnItem.AsyncUpdate := Self;
  FSvnItem.IncludeChangeFiles := True;
  FSvnItem.LogLimit := DefaultRange;
  Application.ProcessMessages;
  FSvnLogFrame.StartAsync;
  FSvnItem.AsyncReloadHistory;
  }
end;

function TLogView.GetCanCloneView: Boolean;
begin
  Result := False;
end;

function TLogView.GetCaption: string;
begin
  Result := sLog;
end;

function TLogView.GetEditorWindowCaption: string;
begin
  Result := sLog;
end;

function TLogView.GetEditState: TEditState;
begin
  Result := [];
  if Assigned(FSvnLogFrame) then
    Result := SvnEditStateToEditState(FSvnLogFrame.SvnEditState);
end;

function TLogView.GetFrameClass: TCustomFrameClass;
begin
  Result := THgLogFrame;
end;

function TLogView.GetImageIndex: Integer;
begin
  Result := 0;
end;

function TLogView.GetTabHintText: string;
begin
  Result := '';
  //TODO: provide a custom hint for the LogView tab
end;

function TLogView.GetViewIdentifier: string;
begin
  Result := sLogView;
end;

procedure TLogView.LoadRevisionsCallBack(FirstRevision, LastRevision, Count: Integer);
begin
  if FirstRevision = -1 then
    FFirst := 0;
  FHgItem.LogLimit := Count;
  FHgItem.LogFirstRev := FirstRevision;
  FHgItem.LogLastRev := LastRevision;
  FHgItem.IncludeChangedFiles := True;
  FHgItem.AsyncUpdate := Self;
  {
  FSvnLogFrame.StartAsync;
  }
  FHgItem.AsyncReloadHistory;
end;

procedure TLogView.ReverseMergeCallBack(const APathName: string; ARevision1,
  ARevision2: Integer);
{
var
  URL, RootURL, Path, PathName: string;
begin
  if APathName = '' then
  begin
    URL := IDEClient.SvnClient.FindRepository(FRootPath);
    Path := SvnExcludeTrailingPathDelimiter(IDEClient.SvnClient.NativePathToSvnPath(FRootPath));
  end
  else
  begin
    URL := IDEClient.SvnClient.FindRepository(FRootPath);
    RootURL := IDEClient.SvnClient.FindRepositoryRoot(FRootPath);
    PathName := APathName;
    if URL <> RootURL then
      Delete(PathName, 1, Length(URL) - Length(RootURL));
    Path := SvnExcludeTrailingPathDelimiter(IDEClient.SvnClient.NativePathToSvnPath(FRootPath));
    URL := URL + PathName;
    Path := Path + PathName;
  end;
  TMergeThread.Create(IDEClient, URL, Path, ARevision1, ARevision2);
}
begin
end;

procedure TLogView.SaveRevisionCallBack(AFileList: TStringList;
  ARevision: Integer; const ADestPath: string);
var
  I: Integer;
  SaveRevisionThread: TSaveRevisionThread;
  RootPath: string;
begin
  SaveRevisionThread := TSaveRevisionThread.Create(ARevision, ADestPath);
  RootPath := IDEClient.HgClient.FindRepositoryRoot(FRootPath) + '\'; //TODO:1
  for I := 0 to AFileList.Count - 1 do
    SaveRevisionThread.AddFile(RootPath + AFileList[I]);
  SaveRevisionThread.Start;
end;

procedure TLogView.SelectView;
begin
  // Not used
end;

procedure TLogView.UpdateHistoryItems(HgItem: THgItem; FirstNewIndex, LastNewIndex: Integer;
  ForceUpdate: Boolean);
var
  I: Integer;
  HistoryItem: THgHistoryItem;
  CanUpdate: Boolean;
begin
  CanUpdate := (FirstNewIndex = 0) or ((LastNewIndex - FFirst <> 0 ) and ((LastNewIndex - FFirst) Mod 20 = 0));
  if CanUpdate or ForceUpdate then
  begin
    FSvnLogFrame.BeginUpdate;
    try
      for I := FFirst to LastNewIndex do
      begin
        HistoryItem := HgItem.HistoryItems[I];
        FSvnLogFrame.AddRevisions(HistoryItem.ChangeSetID, HistoryItem.Date,
          HistoryItem.Author, HistoryItem.Description, '', HistoryItem.ChangedFiles);
      end;
    finally
      FSvnLogFrame.EndUpdate;
    end;
    FFirst := LastNewIndex + 1;
    Application.ProcessMessages;
  end;
end;

function GetView: INTACustomEditorView;
begin
  Result := LogView;
end;

procedure Register;
begin
  (BorlandIDEServices as IOTAEditorViewServices).RegisterEditorView(sLogView, GetView);
end;

function TParentLogHgMenu.GetImageIndex: Integer;
begin
  Result := LogImageIndex;
end;

initialization
finalization
  (BorlandIDEServices as IOTAEditorViewServices).UnRegisterEditorView(sLogView);
end.
