using System;
using Microsoft.AspNetCore.Authorization;
using nscreg.Data.Constants;

namespace nscreg.Server.Core.Authorize
{
    /// <summary>
    /// System function attribute class
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
