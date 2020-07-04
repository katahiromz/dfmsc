program dfmsc;

{$APPTYPE CONSOLE}

{$R *.res}

uses
  System.SysUtils,
  System.Classes;

procedure show_version;
begin
  Writeln('dfmsc by katahiromz version 0.5');
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

procedure ObjectBinaryToText2(const Input, Output: TStream);
var
  NestingLevel: Integer;
  Reader: TReader;
  Writer: TWriter;
  ObjectName, PropName: string;
  UTF8Idents: Boolean;
  MemoryStream: TMemoryStream;
  LFormatSettings: TFormatSettings;

  procedure WriteIndent;
  var
    Buf: TBytes;
    I: Integer;
  begin
    Buf := TBytes.Create($20, $20);
    for I := 1 to NestingLevel do Writer.Write(Buf, Length(Buf));
  end;

  procedure WriteTBytes(S: TBytes);
  begin
    Writer.Write(S, Length(S));
  end;

  procedure WriteAsciiStr(const S: String);
  var
    Buf: TBytes;
    I: Integer;
  begin
    SetLength(Buf, S.Length);
    for I := Low(S) to High(S) do
      Buf[I-Low(S)] := Byte(S[I]);
    Writer.Write(Buf, Length(Buf));
  end;

  procedure WriteByte(const B: Byte);
  begin
    Writer.Write(B, 1);
  end;

  procedure WriteUTF8Str(const S: string);
  var
    Ident: TBytes; // UTF8String;
  begin
    Ident := TEncoding.UTF8.GetBytes(S);

    if not UTF8Idents and (Length(Ident) > S.Length) then
      UTF8Idents := True;
    WriteTBytes(Ident);
  end;

  procedure NewLine;
  begin
    WriteAsciiStr(sLineBreak);
    WriteIndent;
  end;

  procedure ConvertValue; forward;

  procedure ConvertHeader;
  var
    ClassName: string;
    Flags: TFilerFlags;
    Position: Integer;
  begin
    Reader.ReadPrefix(Flags, Position);
    ClassName := Reader.ReadStr;
    ObjectName := Reader.ReadStr;
    WriteIndent;
    if ffInherited in Flags then
      WriteAsciiStr('inherited ')
    else if ffInline in Flags then
      WriteAsciiStr('inline ')
    else
      WriteAsciiStr('object ');
    if ObjectName <> '' then
    begin
      WriteUTF8Str(ObjectName);
      WriteAsciiStr(': ');
    end;
    WriteUTF8Str(ClassName);
    if ffChildPos in Flags then
    begin
      WriteAsciiStr(' [');
      WriteAsciiStr(IntToStr(Position));
      WriteAsciiStr(']');
    end;

    if ObjectName = '' then
      ObjectName := ClassName;  // save for error reporting

    WriteAsciiStr(sLineBreak);
  end;

  procedure ConvertBinary;
  const
    BytesPerLine = 32;
  var
    MultiLine: Boolean;
    I: Integer;
    Count: Integer;
    Buffer: TBytes; // array[0..BytesPerLine - 1] of AnsiChar;
    Text: TBytes; // array[0..BytesPerLine * 2 - 1] of AnsiChar;
  begin
    SetLength(Buffer, BytesPerLine);
    SetLength(Text, BytesPerLine*2+1);

    Reader.ReadValue;
    WriteAsciiStr('{');
    Inc(NestingLevel);
    Reader.Read(Count, SizeOf(Count));
    MultiLine := Count >= BytesPerLine;
    while Count > 0 do
    begin
      if MultiLine then NewLine;
      if Count >= 32 then I := 32 else I := Count;
      Reader.Read(Buffer, I);
      BinToHex(Buffer, 0, Text, 0, I);
      Writer.Write(Text, I * 2);
      Dec(Count, I);
    end;
    Dec(NestingLevel);
    WriteAsciiStr('}');
  end;

  procedure ConvertProperty; forward;

  procedure ConvertValue;
  const
    LineLength = 64;
  var
    I, J, K, L: Integer;
    S: String;
    W: String;
    LineBreak: Boolean;
  begin
    case Reader.NextValue of
      vaList:
        begin
          Reader.ReadValue;
          WriteAsciiStr('(');
          Inc(NestingLevel);
          while not Reader.EndOfList do
          begin
            NewLine;
            ConvertValue;
          end;
          Reader.ReadListEnd;
          Dec(NestingLevel);
          WriteAsciiStr(')');
        end;
      vaInt8, vaInt16, vaInt32:
        WriteAsciiStr(IntToStr(Reader.ReadInteger));
      vaExtended, vaDouble:
        WriteAsciiStr(FloatToStrF(Reader.ReadFloat, ffFixed, 16, 18, LFormatSettings));
      vaSingle:
        WriteAsciiStr(FloatToStr(Reader.ReadSingle, LFormatSettings) + 's');
      vaCurrency:
        WriteAsciiStr(FloatToStr(Reader.ReadCurrency * 10000, LFormatSettings) + 'c');
      vaDate:
        WriteAsciiStr(FloatToStr(Reader.ReadDate, LFormatSettings) + 'd');
      vaWString, vaUTF8String:
        begin
          W := Reader.ReadString;
          L := High(W);
          if L = High('') then WriteAsciiStr('''''') else
          begin
            I := Low(W);
            Inc(NestingLevel);
            try
              if L > LineLength then NewLine;
              K := I;
              repeat
                LineBreak := False;
                if (W[I] >= ' ') and (W[I] <> '''') and (Ord(W[i]) <= 127) then
                begin
                  J := I;
                  repeat
                    Inc(I)
                  until (I > L) or (W[I] < ' ') or (W[I] = '''') or
                    ((I - K) >= LineLength) or (Ord(W[i]) > 127);
                  if ((I - K) >= LineLength) then LineBreak := True;
                  WriteAsciiStr('''');
                  while J < I do
                  begin
                    WriteByte(Byte(W[J]));
                    Inc(J);
                  end;
                  WriteAsciiStr('''');
                end else
                begin
                  WriteAsciiStr('#');
                  WriteAsciiStr(IntToStr(Ord(W[I])));
                  Inc(I);
                  if ((I - K) >= LineLength) then LineBreak := True;
                end;
                if LineBreak and (I <= L) then
                begin
                  WriteAsciiStr(' +');
                  NewLine;
                  K := I;
                end;
              until I > L;
            finally
              Dec(NestingLevel);
            end;
          end;
        end;
      vaString, vaLString:
        begin
          S := Reader.ReadString;
          L := High(S);
          if L = High('') then WriteAsciiStr('''''') else
          begin
            I := Low(S);
            Inc(NestingLevel);
            try
              if L > LineLength then NewLine;
              K := I;
              repeat
                LineBreak := False;
                if (S[I] >= ' ') and (S[I] <> '''') then
                begin
                  J := I;
                  repeat
                    Inc(I)
                  until (I > L) or (S[I] < ' ') or (S[I] = '''') or
                    ((I - K) >= LineLength);
                  if ((I - K) >= LineLength) then
                  begin
                    LIneBreak := True;

//                    if ByteType(S, I) = mbTrailByte then Dec(I);
                  end;
                  WriteAsciiStr('''');

                  WriteAsciiStr(S.Substring(J-Low(S), I-J));
                  WriteAsciiStr('''');
                end else
                begin
                  WriteAsciiStr('#');
                  WriteAsciiStr(IntToStr(Ord(S[I])));
                  Inc(I);
                  if ((I - K) >= LineLength) then LineBreak := True;
                end;
                if LineBreak and (I <= L) then
                begin
                  WriteAsciiStr(' +');
                  NewLine;
                  K := I;
                end;
              until I > L;
            finally
              Dec(NestingLevel);
            end;
          end;
        end;
      vaIdent, vaFalse, vaTrue, vaNil, vaNull:
        WriteUTF8Str(Reader.ReadIdent);
      vaBinary:
        ConvertBinary;
      vaSet:
        begin
          Reader.ReadValue;
          WriteAsciiStr('[');
          I := 0;
          while True do
          begin
            S := Reader.ReadStr;
            if S = '' then Break;
            if I > 0 then WriteAsciiStr(', ');
            WriteUtf8Str(S);
            Inc(I);
          end;
          WriteAsciiStr(']');
        end;
      vaCollection:
        begin
          Reader.ReadValue;
          WriteAsciiStr('<');
          Inc(NestingLevel);
          while not Reader.EndOfList do
          begin
            NewLine;
            WriteAsciiStr('item');
            if Reader.NextValue in [vaInt8, vaInt16, vaInt32] then
            begin
              WriteAsciiStr(' [');
              ConvertValue;
              WriteAsciiStr(']');
            end;
            WriteAsciiStr(sLineBreak);
            Reader.CheckValue(vaList);
            Inc(NestingLevel);
            while not Reader.EndOfList do
              ConvertProperty;
            Reader.ReadListEnd;
            Dec(NestingLevel);
            WriteIndent;
            WriteAsciiStr('end');
          end;
          Reader.ReadListEnd;
          Dec(NestingLevel);
          WriteAsciiStr('>');
        end;
      vaInt64:
        WriteAsciiStr(IntToStr(Reader.ReadInt64));
    else
      raise Exception.Create('ReadError');
    end;
  end;

  procedure ConvertProperty;
  begin
    WriteIndent;
    PropName := Reader.ReadStr;  // save for error reporting
    WriteUTF8Str(PropName);
    WriteAsciiStr(' = ');
    ConvertValue;
    WriteAsciiStr(sLineBreak);
  end;

  procedure ConvertObject;
  begin
    ConvertHeader;
    Inc(NestingLevel);
    while not Reader.EndOfList do
      ConvertProperty;
    Reader.ReadListEnd;
    while not Reader.EndOfList do
      ConvertObject;
    Reader.ReadListEnd;
    Dec(NestingLevel);
    WriteIndent;
    WriteAsciiStr('end' + sLineBreak);
  end;

begin
  NestingLevel := 0;
  UTF8Idents := False;
  Reader := TReader.Create(Input, 4096);
  LFormatSettings := TFormatSettings.Create('en-US'); // do not localize
  LFormatSettings.DecimalSeparator := '.';
  try
    MemoryStream := TMemoryStream.Create;
    try
      Writer := TWriter.Create(MemoryStream, 4096);
      try
        Reader.ReadSignature;
        ConvertObject;
      finally
        Writer.Free;
      end;
      if UTF8Idents then
        Output.Write(TEncoding.UTF8.GetPreamble[0], 3);
      Output.Write(MemoryStream.Memory^, MemoryStream.Size);
    finally
      MemoryStream.Free;
    end;
  finally
    Reader.Free;
  end;
end;

type
  TWriter2 = class(TWriter)
  public
    procedure WritePrefix2(Flags: TFilerFlags; AChildPos: Integer);
  end;

procedure TWriter2.WritePrefix2(Flags: TFilerFlags; AChildPos: Integer);
begin
  WritePrefix(Flags, AChildPos);
end;

procedure ObjectTextToBinary2(const Input, Output: TStream);
var
  Parser: TParser;
  Writer: TWriter2;
  FFmtSettings: TFormatSettings;
  TokenStr: String;

  function ConvertOrderModifier: Integer;
  begin
    Result := -1;
    if Parser.Token = '[' then
    begin
      Parser.NextToken;
      Parser.CheckToken(toInteger);
      Result := Parser.TokenInt;
      Parser.NextToken;
      Parser.CheckToken(']');
      Parser.NextToken;
    end;
  end;

  procedure ConvertHeader(IsInherited, IsInline: Boolean);
  var
    ClassName, ObjectName: string;
    Flags: TFilerFlags;
    Position: Integer;
  begin
    Parser.CheckToken(toSymbol);
    ClassName := Parser.TokenString;
    ObjectName := '';
    if Parser.NextToken = ':' then
    begin
      Parser.NextToken;
      Parser.CheckToken(toSymbol);
      ObjectName := ClassName;
      ClassName := Parser.TokenString;
      Parser.NextToken;
    end;
    Flags := [];
    Position := ConvertOrderModifier;
    if IsInherited then
      Include(Flags, ffInherited);
    if IsInline then
      Include(Flags, ffInline);
    if Position >= 0 then
      Include(Flags, ffChildPos);
    Writer.WritePrefix2(Flags, Position);
    Writer.WriteUTF8Str(ClassName);
    Writer.WriteUTF8Str(ObjectName);
  end;

  procedure ConvertProperty; forward;

  procedure ConvertValue;
  var
    Order: Integer;

    function CombineString: String;
    begin
      Result := Parser.TokenWideString;
      while Parser.NextToken = '+' do
      begin
        Parser.NextToken;
        if not (Parser.Token in [System.Classes.toString, toWString]) then
          Parser.CheckToken(System.Classes.toString);
        Result := Result + Parser.TokenWideString;
      end;
    end;

  begin
    if Parser.Token in [System.Classes.toString, toWString] then
      Writer.WriteString(CombineString)
    else
    begin
      case Parser.Token of
        toSymbol:
          Writer.WriteIdent(Parser.TokenComponentIdent);
        toInteger:
          Writer.WriteInteger(Parser.TokenInt);
        toFloat:
          begin
            case Parser.FloatType of
              's', 'S': Writer.WriteSingle(Parser.TokenFloat);
              'c', 'C': Writer.WriteCurrency(Parser.TokenFloat / 10000);
              'd', 'D': Writer.WriteDate(Parser.TokenFloat);
            else
              Writer.WriteFloat(Parser.TokenFloat);
            end;
          end;
        '[':
          begin
            Parser.NextToken;
            Writer.WriteValue(vaSet);
            if Parser.Token <> ']' then
              while True do
              begin
                TokenStr := Parser.TokenString;
                case Parser.Token of
                  toInteger: begin end;
                  System.Classes.toString,toWString: TokenStr := '#' + IntToStr(Ord(TokenStr.Chars[0]));
                else
                  Parser.CheckToken(toSymbol);
                end;
                Writer.WriteUTF8Str(TokenStr);
                if Parser.NextToken = ']' then Break;
                Parser.CheckToken(',');
                Parser.NextToken;
              end;
            Writer.WriteUTF8Str('');
          end;
        '(':
          begin
            Parser.NextToken;
            Writer.WriteListBegin;
            while Parser.Token <> ')' do ConvertValue;
            Writer.WriteListEnd;
          end;
        '{':
          Writer.WriteBinary(Parser.HexToBinary);
        '<':
          begin
            Parser.NextToken;
            Writer.WriteValue(vaCollection);
            while Parser.Token <> '>' do
            begin
              Parser.CheckTokenSymbol('item');
              Parser.NextToken;
              Order := ConvertOrderModifier;
              if Order <> -1 then Writer.WriteInteger(Order);
              Writer.WriteListBegin;
              while not Parser.TokenSymbolIs('end') do ConvertProperty;
              Writer.WriteListEnd;
              Parser.NextToken;
            end;
            Writer.WriteListEnd;
          end;
      else
        raise Exception.Create('SInvalidProperty');
      end;
      Parser.NextToken;
    end;
  end;

  procedure ConvertProperty;
  var
    PropName: string;
  begin
    Parser.CheckToken(toSymbol);
    PropName := Parser.TokenString;
    Parser.NextToken;
    while Parser.Token = '.' do
    begin
      Parser.NextToken;
      Parser.CheckToken(toSymbol);
      PropName := PropName + '.' + Parser.TokenString;
      Parser.NextToken;
    end;
    Writer.WriteUTF8Str(PropName);
    Parser.CheckToken('=');
    Parser.NextToken;
    ConvertValue;
  end;

  procedure ConvertObject;
  var
    InheritedObject: Boolean;
    InlineObject: Boolean;
  begin
    InheritedObject := False;
    InlineObject := False;
    if Parser.TokenSymbolIs('INHERITED') then
      InheritedObject := True
    else if Parser.TokenSymbolIs('INLINE') then
      InlineObject := True
    else
      Parser.CheckTokenSymbol('OBJECT');
    Parser.NextToken;
    ConvertHeader(InheritedObject, InlineObject);
    while not Parser.TokenSymbolIs('END') and
      not Parser.TokenSymbolIs('OBJECT') and
      not Parser.TokenSymbolIs('INHERITED') and
      not Parser.TokenSymbolIs('INLINE') do
      ConvertProperty;
    Writer.WriteListEnd;
    while not Parser.TokenSymbolIs('END') do ConvertObject;
    Writer.WriteListEnd;
    Parser.NextToken;
  end;
begin
  { Initialize a new TFormatSettings block }
  FFmtSettings := FormatSettings;
  FFmtSettings.DecimalSeparator := '.';

  { Create the parser instance }
  Parser := TParser.Create(Input, FFmtSettings);
  try
    Writer := TWriter2.Create(Output, 4096);
    try
      Writer.WriteSignature;
      ConvertObject;
    finally
      Writer.Free;
    end;
  finally
    Parser.Free;
  end;
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
    ObjectBinaryToText2(SrcS, DestS);
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
    ObjectTextToBinary2(SrcS, DestS);
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

