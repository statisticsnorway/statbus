using Microsoft.AspNetCore.Mvc.Filters;
using System;
using Microsoft.Extensions.Logging;
using Microsoft.AspNetCore.Mvc;
using nscreg.Server.Common;

namespace nscreg.Server.Core
{
    /// <summary>
    /// Фильтр глобальных исключений
    /// </summary>
    public class GlobalExceptionFilter : IExceptionFilter
    {
        private readonly ILogger _logger;

        public GlobalExceptionFilter(ILoggerFactory logger)
        {
            if (logger == null)
            {
                throw new ArgumentNullException(nameof(logger));
            }

            _logger = logger.CreateLogger("Global Exception Filter");
        }
        /// <summary>
        /// Метод вызова обработки исключений
        /// </summary>
        /// <param name="context">Контекст исключений</param>
        public void OnException(ExceptionContext context)
        {
            if (context.Exception.GetType() == typeof(NotFoundException))
            {
                context.Result = new NotFoundObjectResult(new { message = context.Exception.Message });
            }
            else if (context.Exception.GetType() == typeof(BadRequestException))
            {
                context.Result = new BadRequestObjectResult(new { message = context.Exception.Message });
            }
            else
            {
                context.Result = new ObjectResult(new { message = context.Exception.Message })
                {
                    StatusCode = 500
                };
            }

            _logger.LogError(context.Exception.Message, context.Exception);
        }
    }
}
