using System;
using System.Collections.Generic;
using System.Globalization;
using System.IO;
using System.Linq;
using System.Threading.Tasks;
using PeterKottas.DotNetCore.WindowsService;
using PeterKottas.DotNetCore.WindowsService.Interfaces;

namespace nscreg.DataSources.Service
{
    public class Program
    {
        public static void Main(string[] args)
        {

            ServiceRunner<DataQueueService>.Run(config =>
            {
                var name = "nscreg.DataSources.Service";
                config.SetName(name);

                config.Service(serviceConfig =>
                {
                    serviceConfig.ServiceFactory((extraArguments) =>
                    {
                        return new DataQueueService();
                    });
                    serviceConfig.OnStart((service, extraArguments) =>
                    {
                        Console.WriteLine("Service {0} started", name);
                        service.Start();
                    });

                    serviceConfig.OnStop(service =>
                    {
                        Console.WriteLine("Service {0} stopped", name);
                        service.Stop();
                    });

                    serviceConfig.OnError(e =>
                    {
                        Console.WriteLine("Service {0} errored with exception : {1}", name, e.Message);
                    });
                });
            });
        }
    }
}
