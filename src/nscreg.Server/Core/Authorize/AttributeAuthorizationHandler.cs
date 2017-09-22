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
    /// Класс обработчик атрибутов авторизации
    /// </summary>
    /// <typeparam name="TRequirement">Требование</typeparam>
    /// <typeparam name="TAttribute">Аттрибут</typeparam>
    public abstract class AttributeAuthorizationHandler<TRequirement, TAttribute> : AuthorizationHandler<TRequirement>
        where TRequirement : IAuthorizationRequirement
        where TAttribute : Attribute
    {
        /// <summary>
        /// Метод обработчик требования
        /// </summary>
        /// <param name="context">Контекст</param>
        /// <param name="requirement">Требование</param>
        /// <returns></returns>
        protected override Task HandleRequirementAsync(AuthorizationHandlerContext context, TRequirement requirement)
            => HandleRequirementAsync(
                context,
                requirement,
                GetAttributes(((context.Resource as AuthorizationFilterContext)?
                    .ActionDescriptor as ControllerActionDescriptor)?.MethodInfo));

        /// <summary>
        /// Метод обработчик требования
        /// </summary>
        /// <param name="context">Контекст</param>
        /// <param name="requirement">Требование</param>
        /// <param name="attributes">Аттрибут</param>
        /// <returns></returns>
        protected abstract Task HandleRequirementAsync(
            AuthorizationHandlerContext context,
            TRequirement requirement,
            IEnumerable<TAttribute> attributes);

        /// <summary>
        /// Метод получения аттрибутов
        /// </summary>
        /// <param name="memberInfo">Информация участника</param>
        /// <returns></returns>
        private static IEnumerable<TAttribute> GetAttributes(MemberInfo memberInfo) =>
            memberInfo?.GetCustomAttributes(typeof(TAttribute), false).Cast<TAttribute>() ??
            Enumerable.Empty<TAttribute>();
    }
}
