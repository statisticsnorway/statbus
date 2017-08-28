using System;
using System.Linq.Expressions;
using nscreg.Data.Entities;
using Expression = nscreg.Utilities.Models.SampleFrame.Expression;

namespace nscreg.Business.SampleFrame
{
    public interface IExpressionParser
    {
        Expression<Func<StatisticalUnit, bool>> Parse(Expression expression);
    }
}
