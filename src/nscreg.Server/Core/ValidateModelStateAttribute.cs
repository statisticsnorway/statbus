using System.Linq;
using Microsoft.AspNetCore.Mvc;
using Microsoft.AspNetCore.Mvc.Filters;
using ServiceStack;

namespace nscreg.Server.Core
{
    /// <summary>
    ///  Класс валидации модели
    /// </summary>
    public class ValidateModelStateAttribute : ActionFilterAttribute
    {
        /// <summary>
        ///     Метод валидирует модель в Action методы конструктора
        /// </summary>
        /// <param name="context">Контекст данных</param>
        public override void OnActionExecuting(ActionExecutingContext context)
        {
            if (context.Filters.Any(x => x is DisableValidateModelStateAttribute))
                return;
            if (context.ModelState.IsValid)
                base.OnActionExecuting(context);
            else
                context.Result = new BadRequestObjectResult(context.ModelState);
        }
    }
}
