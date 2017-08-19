unit NotifyThreadU;

interface
uses Classes;

type

TResponseCallBack = procedure(Response: string) of Object;
TOnExecuteEvent = procedure(url: string; valCallbackResponse: TResponseCallBack) of Object;

TNotifyThread = class(TThread)
private
  FUrl: string;


protected
  procedure Execute(); override;
public
  onExecute: TOnExecuteEvent;
  callbackResponse: TResponseCallBack;
  property Url: String read FUrl;
  function SetUrl(Value: String):TNotifyThread;
  function SetExecuteHandler(Value: TOnExecuteEvent):TNotifyThread;
  function SetCallBackHandler(callbackResponse: TResponseCallBack):TNotifyThread;
end;

  TNotifyRequestHanldler = class(TObject)
  end;

implementation

procedure TNotifyThread.Execute();
begin
  if Assigned(OnExecute) then
    onExecute(FUrl, callbackResponse);
end;

function TNotifyThread.SetCallBackHandler(callbackResponse: TResponseCallBack):TNotifyThread;
begin
  Self.callbackResponse := callbackResponse;
  Result := self;
end;

function TNotifyThread.SetUrl(Value: String):TNotifyThread;
begin
  FUrl := Value;
  Result := self;
end;

function TNotifyThread.SetExecuteHandler(Value: TOnExecuteEvent):TNotifyThread;
begin
  OnExecute := Value;
  Result := self;
end;

end.
