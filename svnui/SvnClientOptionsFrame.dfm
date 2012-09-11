object SvnOptionsFrame: TSvnOptionsFrame
  Left = 0
  Top = 0
  Width = 465
  Height = 469
  TabOrder = 0
  object GroupBox1: TGroupBox
    Left = 8
    Top = 8
    Width = 305
    Height = 193
    Caption = ' Colors '
    TabOrder = 0
    object Label1: TLabel
      Left = 5
      Top = 48
      Width = 48
      Height = 13
      Caption = 'Conflicted'
      FocusControl = cboxConflicted
    end
    object Label2: TLabel
      Left = 5
      Top = 76
      Width = 31
      Height = 13
      Caption = 'Added'
      FocusControl = cboxAdded
    end
    object Label3: TLabel
      Left = 5
      Top = 104
      Width = 135
      Height = 13
      Caption = 'Missing / Deleted / Replaced'
      FocusControl = cboxDeleted
    end
    object Label4: TLabel
      Left = 5
      Top = 132
      Width = 36
      Height = 13
      Caption = 'Merged'
      FocusControl = cboxMerged
    end
    object Label5: TLabel
      Left = 5
      Top = 160
      Width = 40
      Height = 13
      Caption = 'Modified'
      FocusControl = cboxModified
    end
    object cboxConflicted: TColorBox
      Left = 149
      Top = 45
      Width = 145
      Height = 22
      Style = [cbStandardColors, cbExtendedColors, cbSystemColors, cbIncludeDefault, cbCustomColor, cbPrettyNames]
      TabOrder = 1
    end
    object cboxAdded: TColorBox
      Left = 149
      Top = 73
      Width = 145
      Height = 22
      Style = [cbStandardColors, cbExtendedColors, cbSystemColors, cbIncludeDefault, cbCustomColor, cbPrettyNames]
      TabOrder = 2
    end
    object cboxDeleted: TColorBox
      Left = 149
      Top = 101
      Width = 145
      Height = 22
      Style = [cbStandardColors, cbExtendedColors, cbSystemColors, cbIncludeDefault, cbCustomColor, cbPrettyNames]
      TabOrder = 3
    end
    object cboxMerged: TColorBox
      Left = 149
      Top = 129
      Width = 145
      Height = 22
      Style = [cbStandardColors, cbExtendedColors, cbSystemColors, cbIncludeDefault, cbCustomColor, cbPrettyNames]
      TabOrder = 4
    end
    object cboxModified: TColorBox
      Left = 149
      Top = 157
      Width = 145
      Height = 22
      Style = [cbStandardColors, cbExtendedColors, cbSystemColors, cbIncludeDefault, cbCustomColor, cbPrettyNames]
      TabOrder = 5
    end
    object cbStatusColorsEnabled: TCheckBox
      Left = 5
      Top = 22
      Width = 124
      Height = 17
      Caption = 'Enable Colors'
      TabOrder = 0
    end
  end
  object GroupBox2: TGroupBox
    Left = 8
    Top = 207
    Width = 305
    Height = 122
    Caption = ' Options '
    TabOrder = 1
    object cbDeleteBackupFilesAfterCommit: TCheckBox
      Left = 5
      Top = 22
      Width = 172
      Height = 17
      Caption = 'Delete backup files after commit'
      TabOrder = 0
    end
    object cbKeepCommitViewOpenAfterCommit: TCheckBox
      Left = 5
      Top = 94
      Width = 212
      Height = 17
      Caption = 'Keep Commit View open after commit'
      TabOrder = 3
    end
  end
  object GroupBox5: TGroupBox
    Left = 8
    Top = 335
    Width = 305
    Height = 122
    Caption = ' Blame : Diff options '
    TabOrder = 2
    object IgnoreEOL: TCheckBox
      Left = 5
      Top = 22
      Width = 113
      Height = 17
      Caption = 'Ignore line &endings'
      TabOrder = 0
    end
    object CompareSpace: TRadioButton
      Left = 5
      Top = 53
      Width = 145
      Height = 17
      Caption = '&Compare whitespaces'
      Checked = True
      TabOrder = 1
      TabStop = True
    end
    object IgnoreSpace: TRadioButton
      Left = 5
      Top = 76
      Width = 161
      Height = 17
      Caption = 'Ignore whitespace c&hanges'
      TabOrder = 2
    end
    object IgnoreAllSpace: TRadioButton
      Left = 5
      Top = 99
      Width = 145
      Height = 17
      Caption = 'I&gnore all whitespaces'
      TabOrder = 3
    end
  end
end
