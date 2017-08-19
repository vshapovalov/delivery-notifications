unit NotifyServiceU;

interface

uses
  Windows, Messages, SysUtils, Classes, Graphics, Controls, SvcMgr, Dialogs, NotifyThreadU,
  ExtCtrls, IBDatabase, DB, IBEvents, StrUtils, IdHTTP, IniFiles;

type
  TDeliveryNotifyService = class(TService)
    procedure evt1EventAlert(Sender: TObject; EventName: string; EventCount:
        Integer; var CancelAlerts: Boolean);
    procedure ServiceContinue(Sender: TService; var Continued: Boolean);
    procedure ServiceExecute(Sender: TService);
    procedure ServicePause(Sender: TService; var Paused: Boolean);
    procedure ServiceShutdown(Sender: TService);
    procedure ServiceStart(Sender: TService; var Started: Boolean);
    procedure ServiceStop(Sender: TService; var Stopped: Boolean);
  private
    FThread: TNotifyThread;

    FTimer: TTimer;
    FRetryTimer: TTimer;

    FIsStopped: boolean;
    FLastDate: TDate;

    FHost: string;
    FPort: Integer;
    FMessagesAPIUrl: string;
    FOrdersAPIUrl: string;
    FLogsAPIUrl: string;
    FDatabase: string;

    FIBDatabase: TIBDatabase;
    FIBTransaction: TIBTransaction;
    FIBEvents: TIBEvents;

    FNeedSendMessage: Boolean;
    FNeedSendOrders: Boolean;
    FNeedSendLogs: Boolean;

    FIniFileName: String;
    FLogFileName: String;

    procedure writeLog(textMessage: string);
    function getHttpClient():TIdHTTP;
    procedure initDbConnection();
    procedure clearDbConnection();
    procedure clearLog;
    procedure initSettings();
    procedure doRequest(url:string; callbackResponse: TResponseCallBack);
    procedure doAsyncRequest(url:string; callbackResponse: TResponseCallBack);
    function getIniFile: tinifile;
    function getThread():TNotifyThread;
    procedure initServiceState();
    procedure retryTimerHandler(Sender: TObject);
    procedure setSettingItem(section, itemName, value: string; iniFile: tinifile);
        overload;
    procedure setSettingItem(section, itemName: string; value: Integer; iniFile:
        tinifile); overload;
    procedure setSettingItem(section, itemName: string; value: tdate; iniFile:
        tinifile); overload;
    procedure setSettingItem(section, itemName: string; value: Boolean; iniFile:
        tinifile); overload;
    procedure timerHandler(Sender: TObject);
  public
    procedure chatRequestCallBack(Response: string);
    procedure orderRequestCallBack(Response: string);
    procedure logRequestCallBack(Response: string);
    function GetServiceController: TServiceController; override;
  end;

var
  DeliveryNotifyService: TDeliveryNotifyService;

const
  DatabaseSection: string = 'Database';
  WebServiceSection: string = 'WebService';
  MiscSection: string = 'Misc';

  EVENT_CHAT: string = 'CHAT_MESSAGE_ADDED';
  EVENT_ORDER: string = 'ORDER_ADDED';
  EVENT_LOG: string = 'GET_LOGS';

implementation

{$R *.DFM}

procedure ServiceController(CtrlCode: DWord); stdcall;
begin
  DeliveryNotifyService.Controller(CtrlCode);
end;

procedure TDeliveryNotifyService.chatRequestCallBack(Response: string);
begin
  if (Pos('"result":1',Response)) = 0 then
    FNeedSendMessage := True;
end;

procedure TDeliveryNotifyService.orderRequestCallBack(Response: string);
begin
  if (Pos('"result":1',Response)) = 0 then
    FNeedSendOrders := True;
end;

procedure TDeliveryNotifyService.logRequestCallBack(Response: string);
begin
  if (Pos('"result":1',Response)) = 0 then
    FNeedSendLogs := True;
end;

procedure TDeliveryNotifyService.writeLog(textMessage: string);
var
  myFile:TextFile;
  hFile: Cardinal;
  writeCount: Integer;
  fileMode: Integer;
  fs: TFileStream;
begin
  AssignFile(myFile, FLogFileName);
  if FileExists(FLogFileName) then
    Append(myFile)
  else
    Rewrite(myFile);

  WriteLn(myFile,  FormatDateTime('yyyy.mm.dd hh:nn:ss', Now()) + ': ' + textMessage);
  CloseFile(myFile);
end;



function TDeliveryNotifyService.getThread():TNotifyThread;
begin
  Result := TNotifyThread.Create(true);
  Result.FreeOnTerminate := True;
end;

function TDeliveryNotifyService.getHttpClient():TIdHTTP;
var
  http:TIdHTTP;
begin
  http:=TIdHTTP.Create(nil);
  with http do
  begin
    Host := FHost;
    Port := FPort;
    ReadTimeout := 10000;
    AllowCookies := True;
    HandleRedirects := True;
    ProxyParams.BasicAuthentication := False;
    ProxyParams.ProxyPort := 0;
    Request.ContentLength := -1;
    Request.ContentRangeEnd := 0;
    Request.ContentRangeStart := 0;
    Request.ContentType := 'application/json';
    Request.CustomHeaders.Add('Authorization: key=AAAA9aq9qvU:APA91bFv-rfomipdi8AbL8zJSoKsv8Eu3' +
        '5ZiqW9umTLVUe19RX4s1dT5KbpR7mxNv9Cio4FqmQzsUQFNAz_Y6qtldtSKAwDrO' +
        'tFUlPCRGgBW-udN4ObRz89-RxXXqFC5rtEnQ_F9c9XB');
    Request.Accept := 'text/html, */*';
    Request.BasicAuthentication := False;
    Request.UserAgent := 'Mozilla/3.0 (compatible; Indy Library)';
    HTTPOptions := [hoForceEncodeParams];
  end;

  Result := http;
end;

procedure TDeliveryNotifyService.doAsyncRequest(url:string; callbackResponse: TResponseCallBack);
begin
  getThread().SetUrl(url).SetExecuteHandler(doRequest).SetCallBackHandler(callbackResponse).Resume();
end;

procedure TDeliveryNotifyService.doRequest(url:string; callbackResponse: TResponseCallBack);
var
  http: TIdHTTP;
  response: string;
begin
  http := getHttpClient();
  try
    response := http.get(FHost + ':' + IntToStr(Fport) + url);
    if Assigned(callbackResponse) then
      callbackResponse(response);

    writeLog('response - ' + response);
  except
    on e: Exception do
    begin
      writeLog('error - ' + e.Message);
    end;
  end;
  FreeAndNil(http);

end;

procedure TDeliveryNotifyService.evt1EventAlert(Sender: TObject; EventName:
    string; EventCount: Integer; var CancelAlerts: Boolean);
var
    s: String;
begin
  writeLog('event - ' + EventName);
  if (EventName = EVENT_CHAT) then
  begin
    doAsyncRequest(FMessagesAPIUrl, chatRequestCallBack);
  end;

  if (EventName = EVENT_ORDER) then
  begin
    doAsyncRequest(FOrdersAPIUrl, orderRequestCallBack);
  end;

  if (EventName = EVENT_LOG) then
  begin
    doAsyncRequest(FLogsAPIUrl, logRequestCallBack);
  end;



end;

function TDeliveryNotifyService.GetServiceController: TServiceController;
begin
  Result := ServiceController;
end;

procedure TDeliveryNotifyService.ServiceContinue(Sender: TService; var Continued: Boolean);
begin
//  FThread.Resume();
end;

procedure TDeliveryNotifyService.ServiceExecute(Sender: TService);
begin
  while not Sender.Terminated and not FIsStopped do
  begin
    Sleep(1);
    ServiceThread.ProcessRequests(False);
  end;
end;

procedure TDeliveryNotifyService.ServicePause(Sender: TService; var Paused: Boolean);
begin
//  FThread.Suspend();
end;

procedure TDeliveryNotifyService.ServiceShutdown(Sender: TService);
begin
  writeLog('service shutdowning');
  FisStopped:=True;
  FTimer.Enabled := False;
  FTimer.Free;
  FRetryTimer.Enabled := False;
  FRetryTimer.Free;
  clearDbConnection();
end;


procedure TDeliveryNotifyService.clearDbConnection();
begin
  try
    if (FIBDatabase <> nil) then
    begin
      FIBEvents.UnRegisterEvents();
      FreeAndNil(FIBEvents);
      FIBTransaction.Active := false;
      FreeAndNil(FIBTransaction);
      FIBDatabase.Connected := false;
      FreeAndNil(FIBDatabase);
    end;
  except
    on e: exception do
    begin
      writeLog('db clear - ' + e.Message);
    end;
  end;
end;

procedure TDeliveryNotifyService.clearLog;
begin
  if (FLastDate <> Date()) then
  begin
    try
      if (FileExists(FLogFileName)) then
        DeleteFile(FLogFileName);
    except
      on e: Exception do
        writeLog('clearLog: ' + e.Message);
    end;
  end;
end;

function TDeliveryNotifyService.getIniFile: tinifile;
begin
  Result := TIniFile.Create( FIniFileName );
end;

procedure TDeliveryNotifyService.initDbConnection();
begin

  FIBTransaction := TIBTransaction.Create(nil);
  FIBEvents := TIBEvents.Create(nil);
  FIBDatabase := TIBDatabase.Create(nil);

  with FIBTransaction do
  begin
    DefaultAction := TACommitRetaining;
    AutoStopAction := saNone;
  end;

  with (FIBDatabase) do
  begin
    DatabaseName := FDatabase;
    Params.Add('user_name=sysdba');
    Params.Add('password=masterkey');
    Params.Add('lc_ctype=WIN1251');
    LoginPrompt := False;
    DefaultTransaction := FIBTransaction;
    IdleTimer := 0;
    SQLDialect := 3;
    TraceFlags := [];
  end;

  FIBTransaction.DefaultDatabase := FIBDatabase;
  with FIBEvents do
  begin
    AutoRegister := False;
    Database := FIBDatabase;
    Events.Add(EVENT_CHAT);
    Events.Add(EVENT_ORDER);
    Events.Add(EVENT_LOG);
    Registered := False;
    OnEventAlert := evt1EventAlert;
  end;

  try
    FIBDatabase.Open();
    FIBTransaction.Active := true;
    FIBEvents.RegisterEvents();
  except
    on e: Exception do
    begin
      writeLog('db init - ' + e.Message);
    end;
  end;

end;

procedure TDeliveryNotifyService.initServiceState();
begin
  FTimer := TTimer.Create(nil);
  FTimer.Interval := 60000;
  FTimer.Enabled := true;
  FTimer.OnTimer := timerHandler;

  FRetryTimer := TTimer.Create(nil);
  FRetryTimer.Interval := 5000;
  FRetryTimer.Enabled := true;
  FRetryTimer.OnTimer := retryTimerHandler;

  if not (DirectoryExists( IncludeTrailingBackslash( ExtractFilePath(ParamStr(0))) + 'logs')) then
    CreateDir(DirectoryExists( IncludeTrailingBackslash( ExtractFilePath(ParamStr(0))) + 'logs'));

  FIsStopped := False;
  FNeedSendMessage := False;
  FNeedSendOrders := False;
end;



procedure TDeliveryNotifyService.initSettings();
var
  ini: TIniFile;
begin
  ini := getIniFile();
  try
    FHost := ini.ReadString(WebServiceSection, 'host', 'http://dr-sharp.ddns.net');
    FPort := ini.ReadInteger(WebServiceSection, 'port', 80);
    FMessagesAPIUrl := ini.ReadString(WebServiceSection, 'MessagesAPIUrl', '/api/fcm/notify/messages');
    FOrdersAPIUrl := ini.ReadString(WebServiceSection, 'OrdersAPIUrl', '/api/fcm/notify/orders');
    FLogsAPIUrl := ini.ReadString(WebServiceSection, 'LogsAPIUrl', '/api/fcm/notify/logs');
    FDatabase := ini.ReadString(DatabaseSection, 'Database', 'localhost:C:\projects\delphi\delivery\bin\db\delivery.fdb');
    FLastDate := ini.ReadDate(MiscSection, 'CurrentDate',Date());
  except
    on e: Exception do
    begin
      writeLog('settings reading - ' + e.Message);
    end;
  end;
  FreeAndNil(ini);
end;

procedure TDeliveryNotifyService.retryTimerHandler(Sender: TObject);
begin
  if (FNeedSendMessage) then
  begin
    writeLog('retry message');
    FNeedSendMessage := false;
    doAsyncRequest(FMessagesAPIUrl, chatRequestCallBack);
  end;

  if (FNeedSendOrders) then
  begin
    writeLog('retry orders');
    FNeedSendOrders := false;
    doAsyncRequest(FOrdersAPIUrl, orderRequestCallBack);
  end;

  if (FNeedSendLogs) then
  begin
    writeLog('retry logs');
    FNeedSendLogs := false;
    doAsyncRequest(FLogsAPIUrl, logRequestCallBack);
  end;

end;

procedure TDeliveryNotifyService.ServiceStart(Sender: TService; var Started: Boolean);
begin
  Started := true;

  FLogFileName := IncludeTrailingBackslash(ExtractFilePath(ParamStr(0))) + '\logs\log.txt';
  FIniFileName := IncludeTrailingBackslash(ExtractFilePath(ParamStr(0))) + 'settings.ini';

  initSettings();
  initDbConnection();
  initServiceState();

  writeLog('service started');
end;

procedure TDeliveryNotifyService.ServiceStop(Sender: TService; var Stopped: Boolean);
begin
  FIsStopped := True;
  Stopped := True;
  writeLog('service stopped');
end;

procedure TDeliveryNotifyService.setSettingItem(section, itemName, value:
    string; iniFile: tinifile);
var
  lIniFile: TIniFile;
begin
  if (iniFile <> nil) then
    lIniFile := iniFile
  else
    lIniFile := getIniFile();

  lIniFile.WriteString(section, itemName, value);

  if (iniFile = nil) then
    FreeAndNil(lIniFile);
end;

procedure TDeliveryNotifyService.setSettingItem(section, itemName: string;
    value: Integer; iniFile: tinifile);
var
  lIniFile: TIniFile;
begin
  if (iniFile <> nil) then
    lIniFile := iniFile
  else
    lIniFile := getIniFile();

  lIniFile.WriteInteger(section, itemName, value);

  if (iniFile = nil) then
    FreeAndNil(lIniFile);
end;

procedure TDeliveryNotifyService.setSettingItem(section, itemName: string;
    value: tdate; iniFile: tinifile);
var
  lIniFile: TIniFile;
begin
  if (iniFile <> nil) then
    lIniFile := iniFile
  else
    lIniFile := getIniFile();

  lIniFile.WriteDate(section, itemName, value);

  if (iniFile = nil) then
    FreeAndNil(lIniFile);
end;

procedure TDeliveryNotifyService.setSettingItem(section, itemName: string;
    value: Boolean; iniFile: tinifile);
var
  lIniFile: TIniFile;
begin
  if (iniFile <> nil) then
    lIniFile := iniFile
  else
    lIniFile := getIniFile();

  lIniFile.WriteBool(section, itemName, value);

  if (iniFile = nil) then
    FreeAndNil(lIniFile);
end;

procedure TDeliveryNotifyService.timerHandler(Sender: TObject);
begin
  setSettingItem(MiscSection,'CurrentDate', Date(),nil);
  clearDbConnection();
  initDbConnection();
end;

end.
