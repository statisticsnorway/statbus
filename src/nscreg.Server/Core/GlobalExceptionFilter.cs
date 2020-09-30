using Microsoft.AspNetCore.Mvc.Filters;
using System;
using Microsoft.Extensions.Logging;
using Microsoft.AspNetCore.Mvc;
using nscreg.Server.Common;

namespace nscreg.Server.Core
{
    /// <summary>
    /// Global Exclusion Filter
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
        /// Exception handling call method Exception handling call method
        /// </summary>
        /// <param name="context">Exception context</param>
        public void OnException(ExceptionContext context)
        {
            switch (context.Exception)
            {
                case NotFoundException _:
                    context.Result = new NotFoundObjectResult(new { message = context.Exception.Message });
                    break;
                case BadRequestException _:
                    context.Result = new BadRequestObjectResult(new { message = context.Exception.Message });
                    break;
                case NullReferenceException _:
                    context.Result = new ObjectResult(new {message = context.Exception.ToString()}) {StatusCode = 500};
                    break;
                default:
                    context.Result = new ObjectResult(new { message = context.Exception.Message })
                    {
                        StatusCode = 500
                    };
                    break;
            }
            _logger.LogError(context.Exception, context.Exception.ToString());
        }
    }
}
