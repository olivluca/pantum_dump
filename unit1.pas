unit Unit1;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Forms, Controls, Graphics, Dialogs, StdCtrls;

type

  { TDumpForm }

  { TPrinter }

  TPrinter = class
  private
    st:TFileStream;
    FLastError:integer;
    FLastErrorDesc:string;
    FBuffer:string;
  public
    constructor create;
    destructor destroy;override;
    procedure SendString(const m:string);
    property lasterror:integer read FLastError;
    property LastErrorDesc:string read FLastErrorDesc;
    function Read:string;
  end;

  TDumpForm = class(TForm)
    btnDump: TButton;
    btnDumpRam: TButton;
    btnDumpSpi: TButton;
    btnDumpOtp: TButton;
    DumpAddress: TEdit;
    DumpLen: TEdit;
    Label1: TLabel;
    Label2: TLabel;
    Memo1: TMemo;
    SaveDialog1: TSaveDialog;
    procedure btnDumpClick(Sender: TObject);
    procedure btnDumpRamClick(Sender: TObject);
    procedure btnDumpSpiClick(Sender: TObject);
    procedure btnDumpOtpClick(Sender: TObject);
    procedure btnDumpToScreenClick(Sender: TObject);
  private
    FPrinter:TPrinter;
    procedure DoDump(const filename:string);
    function Perror(const m:String):boolean;
    procedure SendCommand(const c: string);
  public
    procedure ShowData(const prefix,x:string; decode:boolean);
  end;

var
  DumpForm: TDumpForm;

implementation

{$R *.lfm}

{ TPrinter }

constructor TPrinter.create;
begin
  try
    st:=TFileStream.Create('/dev/usb/lp0',fmOpenReadWrite);

  except
    on e:exception do
    begin
      FLastError:=1;
      FLastErrorDesc:=e.Message;
    end;
  end;
  SetLength(FBuffer,1000);
end;

destructor TPrinter.destroy;
begin
  st.free;
  inherited destroy;
end;

procedure TPrinter.SendString(const m: string);
begin
  try
    st.Write(m[1],length(m));

  except
    on e:exception do
    begin
      FLastError:=1;
      FLastErrorDesc:=e.Message;
    end;
  end;
end;

function TPrinter.Read: string;
var
  x: LongInt;
begin
  result:='';
  x:=st.Read(Fbuffer[1],Length(FBuffer));
  if x>0 then
    result:=copy(FBuffer,1,x)
end;


{ TDumpForm }

procedure TDumpForm.SendCommand(const c:string);
begin
  Memo1.Lines.Add('-----[SendCommand]-----');
  ShowData('> ',c,false);
  FPrinter.SendString(#27'%-12345X@PJL ENTER LANGUAGE=ACL'#13#10);
  if perror('send switch to acl') then
     exit;
  FPrinter.SendString(c);
  if perror('send acl command') then
     exit;
  FPrinter.SendString(#27'%-12345X');
  if perror('send execute command') then
     exit;
end;

procedure TDumpForm.ShowData(const prefix,x: string; decode:boolean);
var
  x2: String;
  y: Integer;
  decodedword:dword;
begin
  x2:=inttostr(length(x))+' - ';
  for y:=1 to length(x) do
    x2:=x2+inttohex(ord(x[y]),2)+' ';
  x2:=x2+':';
  for y:=1 to length(x) do
    if x[y]>' ' then
      x2:=x2+x[y]
    else
      x2:=x2+'.';
  if decode then
  begin
    if length(x)=4 then
    begin
      move(x[1],decodedword,4);
      decodedword:=LEtoN(decodedword);
      x2:=x2+' '+inttostr(decodedword);
    end;
    if length(x)=1 then
      x2:=x2+' '+inttostr(ord(x[1]));
  end;
  memo1.lines.add(prefix+x2);
  Application.ProcessMessages;
end;

procedure TDumpForm.btnDumpClick(Sender: TObject);
begin
  if not SaveDialog1.Execute then
     exit;
  DoDump(SaveDialog1.Filename);
end;

procedure TDumpForm.btnDumpRamClick(Sender: TObject);
begin
  dumpaddress.text:='0';
  dumplen.text:=inttostr(128*1024*1024);
  SaveDialog1.FileName:='ram';
  btnDumpClick(nil);
end;

procedure TDumpForm.btnDumpSpiClick(Sender: TObject);
begin
  dumpaddress.text:='$f6000000';
  dumplen.text:=inttostr(18*1024*1024);
  SaveDialog1.FileName:='spi';
  btnDumpClick(nil);
end;

procedure TDumpForm.btnDumpOtpClick(Sender: TObject);
begin
  dumpaddress.text:='$fd0d0000';
  dumplen.text:='256';
  SaveDialog1.FileName:='otp';
  btnDumpClick(nil);
end;

procedure TDumpForm.btnDumpToScreenClick(Sender: TObject);
begin
  DoDump('');
end;

function TDumpForm.Perror(const m: String): boolean;
begin
  result:=FPrinter.LastError<>0;
  if result then
    memo1.lines.add(m+': '+FPrinter.LastErrorDesc);
end;

procedure TDumpForm.DoDump(const filename:string);
var
  f: TStream;
  x: LongInt;
  buffer: string;
  strlen: string;
  straddr, hdr: string;
  len: dword;
  addr: dword;
  tries: Integer;
  toread: Integer;
begin
  FPrinter:=TPrinter.create;
  if Perror('open printer') then
    exit;
  memo1.lines.add('--- dumping to file '+filename);
  DeleteFile(FileName);
  f:=TFileStream.Create(FileName, fmOpenWrite or fmCreate);
  screen.BeginWaitCursor;
  try
    addr:=StrToInt(DumpAddress.Text);
    addr:=NtoBe(addr);
    len:=StrToInt(DumpLen.Text);
    len:=NToBe(len);
    setlength(straddr, 4);
    move(addr, straddr[1], 4);
    setlength(strlen, 4);
    move(len, strlen[1], 4);
    SendCommand(#00#$ac#00#$09+straddr+strlen+#00#00#00#00);
    setlength(buffer, 1024);
    sleep(1000);
    toread:=16;
    tries:=0;
    hdr:='';
    while toread>0 do
    begin
      x:=FPrinter.st.Read(buffer[1], toread);
      if x>0 then
        hdr:=hdr+copy(buffer,1,x);
      toread:=toread-x;
      if toread>0 then
      begin
         tries:=tries+1;
         if tries>100 then
         begin
            memo1.lines.add('error header');
            exit;
         end;
         sleep(100);
      end;
    end;
    ShowData('< ',hdr,false);
    len:=BeToN(len);
    while len>0 do
    begin
      toread:=1000;
      if toread>len then
        toread:=len;
      x:=FPrinter.st.read(buffer[1], toread);
      f.write(buffer[1], x);
      len:=len-x;
    end;
    memo1.lines.add('done');
  finally
    screen.EndWaitCursor;
    f.free;
    FreeAndNil(FPrinter);
  end;
end;

end.

