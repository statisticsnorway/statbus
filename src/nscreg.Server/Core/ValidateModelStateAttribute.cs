using System.Linq;
using Microsoft.AspNetCore.Mvc;
using Microsoft.AspNetCore.Mvc.Filters;
using ServiceStack;

namespace nscreg.Server.Core
{
    /// <summary>
    ///  Model Validation Class
    /// </summary>
    public class ValidateModelStateAttribute : ActionFilterAttribute
    {
        /// <summary>
        ///     Method validates model in Action constructor methods
        /// </summary>
        /// <param name="context">Data context</param>
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
