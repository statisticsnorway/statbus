using System;
using Microsoft.AspNetCore.Authorization;
using nscreg.Data.Constants;

namespace nscreg.Server.Core.Authorize
{
    /// <summary>
    /// Класс аттрибутов системных функций
    /// </summary>
    [AttributeUsage(AttributeTargets.Method)]
    public class SystemFunctionAttribute : AuthorizeAttribute
    {
        public SystemFunctionAttribute(params SystemFunctions[] allowedFunctions) : base(nameof(SystemFunctions))
        {
            SystemFunctions = allowedFunctions;
        }

        public SystemFunctions[] SystemFunctions { get; }
    }
}
