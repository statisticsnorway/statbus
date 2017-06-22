using System;
using System.Collections.Generic;
using System.Linq;
using System.Reflection;
using System.Threading.Tasks;
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc.Controllers;
using Microsoft.AspNetCore.Mvc.Filters;

namespace nscreg.Server.Core.Authorize
{
    public abstract class AttributeAuthorizationHandler<TRequirement, TAttribute> : AuthorizationHandler<TRequirement>
        where TRequirement : IAuthorizationRequirement
        where TAttribute : Attribute
    {
        protected override Task HandleRequirementAsync(AuthorizationHandlerContext context, TRequirement requirement)
            => HandleRequirementAsync(
                context,
                requirement,
                GetAttributes(((context.Resource as AuthorizationFilterContext)?
                    .ActionDescriptor as ControllerActionDescriptor)?.MethodInfo));

        protected abstract Task HandleRequirementAsync(
            AuthorizationHandlerContext context,
            TRequirement requirement,
            IEnumerable<TAttribute> attributes);

        private static IEnumerable<TAttribute> GetAttributes(MemberInfo memberInfo) =>
            memberInfo?.GetCustomAttributes(typeof(TAttribute), false).Cast<TAttribute>() ??
            Enumerable.Empty<TAttribute>();
    }
}
