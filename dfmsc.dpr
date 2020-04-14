program dfmsc;

{$APPTYPE CONSOLE}

{$R *.res}

uses
  System.SysUtils,
  System.Classes;

procedure show_version;
begin
  Writeln('dfmsc by katahiromz version 0.2');
end;

procedure show_help;
begin
  Writeln('dfmsc: DFM smart converter');
  Writeln('Usage: dfmsc [options] [input_file]');
  Writeln('Options:');
  Writeln('--help     Show this message');
  Writeln('--version  Show version information');
  Writeln('--b2t      Convert from binary to text');
  Writeln('--t2b      Convert from text to binary');
end;

// convert a binary dfm file to a text dfm file
function Dfm2Txt(Src, Dest: string): boolean;
var
  SrcS, DestS: TFileStream;
begin
  if Src = Dest then
  begin
    writeln('ERROR: The source and destination are the same');
    result := False;
    exit;
  end;
  DeleteFile(Dest);
  SrcS := TFileStream.Create(Src, fmOpenRead);
  DestS := TFileStream.Create(Dest, fmCreate);
  try
    ObjectBinaryToText(SrcS, DestS);
    if FileExists(Src) and FileExists(Dest) then
      Result := True
    else
      Result := False;
  finally
    SrcS.Free;
    DestS.Free;
  end;
end;

// convert a text DFM file to a binary DFM file
function Txt2DFM(Src, Dest: string): boolean;
var
  SrcS, DestS: TFileStream;
begin
  if Src = Dest then
  begin
    writeln('ERROR: The source and destination are the same');
    Result := False;
    exit;
  end;
  DeleteFile(Dest);
  SrcS := TFileStream.Create(Src, fmOpenRead);
  DestS := TFileStream.Create(Dest, fmCreate);
  try
    ObjectTextToBinary(SrcS, DestS);
    if FileExists(Src) and FileExists(Dest) then
      Result := True
    else
      Result := False;
  finally
    SrcS.Free;
    DestS.Free;
  end;
end;

var
  index : Integer;
  str, input_file, output_file : String;
  b2t : boolean;
  t2b : boolean;
begin
  b2t := false;
  t2b := false;
  if (ParamCount = 0) then begin
    show_help;
    exit;
  end;
  for index := 1 to ParamCount do begin
    str := ParamStr(index);
    if (str = '--help') then begin
      show_help;
      exit;
    end;
    if (str = '--version') then begin
      show_version;
      exit;
    end;
    if (str = '--b2t') then begin
      b2t := true;
      continue;
    end;
    if (str = '--t2b') then begin
      t2b := true;
      continue;
    end;
    if (str[1] = '-') then begin
      Writeln('ERROR: Invalid option: ''' + str + '''');
      show_help;
      exit;
    end;
    if (Length(input_file) <> 0) then begin
      Writeln('ERROR: Too many input files');
      show_help;
      exit;
    end;
    input_file := str;
  end;
  if (b2t and t2b) then begin
    Writeln('ERROR: You cannot specify both ''--b2t'' and ''--t2b''');
    exit;
  end;
  if (not(b2t) and not(t2b)) then begin
    Writeln('ERROR: You must specify either ''--b2t'' or ''--t2b''');
    exit;
  end;
  if b2t then begin
    output_file := input_file + '.txt';
    if not(Dfm2Txt(input_file, output_file)) then begin
      Writeln('ERROR: Cannot convert file ''' + input_file + '''');
    end;
  end
  else if t2b then begin
    output_file := input_file + '.dfm';
    if not(Txt2Dfm(input_file, output_file)) then begin
      Writeln('ERROR: Cannot convert file ''' + input_file + '''');
    end;
  end;
end.

