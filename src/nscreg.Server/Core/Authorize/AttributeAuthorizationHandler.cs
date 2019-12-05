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
    /// <summary>
    /// Authorization Attribute Handler Class
    /// </summary>
    /// <typeparam name="TRequirement">Requirement</typeparam>
    /// <typeparam name="TAttribute">Attribute</typeparam>
    public abstract class AttributeAuthorizationHandler<TRequirement, TAttribute> : AuthorizationHandler<TRequirement>
        where TRequirement : IAuthorizationRequirement
        where TAttribute : Attribute
    {
        /// <summary>
        /// Requirement Handler Method
        /// </summary>
        /// <param name="context">context</param>
        /// <param name="requirement">requirement</param>
        /// <returns></returns>
        protected override Task HandleRequirementAsync(AuthorizationHandlerContext context, TRequirement requirement)
            => HandleRequirementAsync(
                context,
                requirement,
                GetAttributes(((context.Resource as AuthorizationFilterContext)?
                    .ActionDescriptor as ControllerActionDescriptor)?.MethodInfo));

        /// <summary>
        /// Requirement Handler Method
        /// </summary>
        /// <param name="context">context</param>
        /// <param name="requirement">requirement</param>
        /// <param name="attributes">attributes</param>
        /// <returns></returns>
        protected abstract Task HandleRequirementAsync(
            AuthorizationHandlerContext context,
            TRequirement requirement,
            IEnumerable<TAttribute> attributes);

        /// <summary>
        /// attribute getting method
        /// </summary>
        /// <param name="memberInfo">Member info</param>
        /// <returns></returns>
        private static IEnumerable<TAttribute> GetAttributes(MemberInfo memberInfo) =>
            memberInfo?.GetCustomAttributes(typeof(TAttribute), false).Cast<TAttribute>() ??
            Enumerable.Empty<TAttribute>();
    }
}
