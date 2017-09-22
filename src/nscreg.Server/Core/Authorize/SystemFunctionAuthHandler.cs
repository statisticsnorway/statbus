using System.Collections.Generic;
using System.Linq;
using System.Security.Claims;
using System.Threading.Tasks;
using Microsoft.AspNetCore.Authorization;
using nscreg.Data.Constants;
using nscreg.Server.Common.Services.Contracts;

namespace nscreg.Server.Core.Authorize
{
    // ReSharper disable once ClassNeverInstantiated.Global
    /// <summary>
    /// Класс обработчик авторизации системной функции 
    /// </summary>
    public class SystemFunctionAuthHandler :
        AttributeAuthorizationHandler<SystemFunctionAuthRequirement, SystemFunctionAttribute>
    {
        private readonly IUserService _userService;

        public SystemFunctionAuthHandler(IUserService userService)
        {
            _userService = userService;
        }
        /// <summary>
        /// Метод обработчик требований
        /// </summary>
        /// <param name="context">Контекст данных</param>
        /// <param name="requirement">Требование</param>
        /// <param name="attributes">Аттрибуты</param>
        /// <returns></returns>
        protected override async Task HandleRequirementAsync(AuthorizationHandlerContext context,
            SystemFunctionAuthRequirement requirement,
            IEnumerable<SystemFunctionAttribute> attributes)
        {
            foreach (var attribute in attributes)
                if (!await AuthorizeAsync(context.User, attribute.SystemFunctions))
                {
                    context.Fail();
                    return;
                }
            context.Succeed(requirement);
        }
        /// <summary>
        /// Метод авторизации 
        /// </summary>
        /// <param name="user">Пользователь</param>
        /// <param name="permissions">Разрешения</param>
        /// <returns></returns>
        private async Task<bool> AuthorizeAsync(ClaimsPrincipal user, SystemFunctions[] permissions)
            => (await _userService.GetSystemFunctionsByUserId(user.GetUserId())).Intersect(permissions).Any();
    }
}
