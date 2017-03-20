using System;
using Microsoft.AspNetCore.Authorization;
using nscreg.Data.Constants;

namespace nscreg.Server.Core.Authorize
{
    [AttributeUsage(AttributeTargets.Method)]
    public class SystemFunctionAttribute : AuthorizeAttribute
    {
        public SystemFunctionAttribute(SystemFunctions name) : base(nameof(SystemFunctions))
        {
            Name = name;
        }

        public SystemFunctions Name { get; }
    }
}