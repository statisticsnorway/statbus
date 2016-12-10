using Microsoft.AspNetCore.Mvc;
using Microsoft.AspNetCore.Mvc.Filters;
using System;
using System.Collections.Generic;
using System.Linq;

namespace nscreg.Server.Core
{
    public class ValidateModelNotNullAttribute : ActionFilterAttribute
    {
        private readonly Func<Dictionary<string, object>, bool> _validate;

        public ValidateModelNotNullAttribute(Func<Dictionary<string, object>, bool> checkCondition)
        {
            _validate = checkCondition;
        }

        public ValidateModelNotNullAttribute() : this(args => args.ContainsValue(null))
        {
        }

        public override void OnActionExecuting(ActionExecutingContext context)
        {
            if (_validate(context.ActionArguments.ToDictionary(x => x.Key, x => x.Value)))
                base.OnActionExecuting(context);
            else
                context.Result = new BadRequestObjectResult("argument can't be null");
        }
    }
}
