using System;
using System.Threading;
using PeterKottas.DotNetCore.WindowsService.Base;
using PeterKottas.DotNetCore.WindowsService.Interfaces;

namespace nscreg.DataSources.Service
{
    public class DataQueueService : MicroService, IMicroService
    {
        public void Start()
        {
            StartBase();
            Timers.Start("Queue", 100, () =>
            {
                Console.WriteLine("Metadata");
                Thread.Sleep(1000);
                //ON TIMER
            }, e =>
            {
                //EXCEPTION HANDLER
            });
        }

        public void Stop()
        {
            StopBase();
        }
    }
}