using System;
using System.Linq.Expressions;
using Microsoft.AspNetCore.Mvc.ModelBinding;
using Microsoft.AspNetCore.Mvc.ViewFeatures;

namespace nscreg.Utilities
{
    /// <summary>
    /// Expression utilities comparison class
    /// </summary>
    public static class ExpressionUtils
    {
        private static readonly ModelExpressionProvider ModelExpressionProvider =
            new ModelExpressionProvider(new EmptyModelMetadataProvider());

        /// <summary>
        /// Method for obtaining a text expression
        /// </summary>
        /// <param name = "expr"> Expression </param>
        /// <returns> </returns>
        public static string GetExpressionText<T>(Expression<Func<T, object>> expr) => ModelExpressionProvider.GetExpressionText(expr);
    }
}
