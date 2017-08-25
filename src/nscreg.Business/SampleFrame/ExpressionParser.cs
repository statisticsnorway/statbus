using System;
using nscreg.Data.Entities;
using nscreg.Utilities.Models.SampleFrame;
using LinqExpression = System.Linq.Expressions.Expression;

namespace nscreg.Business.SampleFrame
{
    public class ExpressionParser : IExpressionParser
    {
        public string Parse(Expression expression)
        {
            var result = string.Empty;
            if (expression.ExpressionItem == null) return result;
            
      //      var result = context.StatisticalUnits.Where(x => x.Name == "Soap");
            var item = LinqExpression.Parameter(typeof(StatisticalUnit), "x");
            var prop = LinqExpression.Property(item, expression.ExpressionItem.Field.ToString());
            var soap = LinqExpression.Constant(expression.ExpressionItem.Value);
            var equal = LinqExpression.Equal(prop, soap);
            var lambda = LinqExpression.Lambda<Func<StatisticalUnit, bool>>(equal, item);

            var rr = context.StatisticalUnits.Where(lambda);
        }
    }
}
