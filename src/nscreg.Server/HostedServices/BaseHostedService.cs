using Microsoft.Extensions.Hosting;
using NLog;
using System;
using System.Threading;
using System.Threading.Tasks;

namespace nscreg.Server.HostedServices
{
    /// <summary>
    /// Базовый класс
    /// </summary>
    public class BaseHostedService : IHostedService, IDisposable
    {
        /// <summary>
        /// Логгер
        /// </summary>
        protected ILogger Logger;
        /// <summary>
        /// Таймер
        /// </summary>
        protected Timer Timer;
        /// <summary>
        /// Интервал времени с которым выполнять задачу
        /// </summary>
        protected TimeSpan? TimerInterval;


        protected IServiceProvider Services;

        /// <summary>
        /// Количество зашедгих потоков
        /// </summary>
        protected volatile int Runs = 0;

        /// <summary>
        /// Состояние, 1-занят, 0 - свободен
        /// </summary>
        protected volatile int State = 0;

        /// <summary>
        ///
        /// </summary>
        protected Func<Task> Action { get; set; }

        /// <summary>
        /// Конструктор
        /// </summary>
        /// <param name="services"></param>
        public BaseHostedService(IServiceProvider services)
        {
            Services = services;
        }

        private async void DoWorkAsync(object state)
        {
            if (Interlocked.CompareExchange(ref State, 1, 0) == 1)
            {
                return;
            }

            try
            {
                Interlocked.Increment(ref Runs);
                await Action();
            }
            catch (Exception ex)
            {
                Logger.Log(LogLevel.Error, ex, $"Error while {GetType().Name} do work");
            }
            finally
            {
                Interlocked.Exchange(ref State, 0);
            }
        }

        /// <summary>
        /// Действие на старте сервиса
        /// </summary>
        public Task StartAsync(CancellationToken cancellationToken)
        {
            if (TimerInterval.HasValue)
            {
                Timer = new Timer(DoWorkAsync, null, TimeSpan.Zero, TimerInterval.Value);
            }

            else
            {
                DoWorkAsync(null);
            }

            return Task.CompletedTask;
        }

        /// <summary>
        /// Действие на завершение работы сервиса
        /// </summary>
        /// <param name="cancellationToken"></param>
        /// <returns></returns>
        public Task StopAsync(CancellationToken cancellationToken)
        {
            Timer?.Change(Timeout.Infinite, 0);
            return Task.FromResult(true);
        }

        /// <summary>
        /// Очистка неуправляемых ресурсов
        /// </summary>
        public void Dispose()
        {
            Timer?.Dispose();
        }
    }
}
