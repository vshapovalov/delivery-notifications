object DeliveryNotifyService: TDeliveryNotifyService
  OldCreateOrder = False
  DisplayName = 'Delivery Mobile Notifier'
  OnContinue = ServiceContinue
  OnExecute = ServiceExecute
  OnPause = ServicePause
  OnShutdown = ServiceShutdown
  OnStart = ServiceStart
  OnStop = ServiceStop
  Left = 192
  Top = 167
  Height = 218
  Width = 286
end
