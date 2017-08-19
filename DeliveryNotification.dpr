program DeliveryNotification;

uses
  SvcMgr,
  NotifyServiceU in 'NotifyServiceU.pas' {DeliveryNotifyService: TService},
  NotifyThreadU in 'NotifyThreadU.pas';

{$R *.RES}

begin
  Application.Initialize;
  Application.CreateForm(TDeliveryNotifyService, DeliveryNotifyService);
  Application.Run;
end.
