using System;
using System.Linq.Expressions;
using nscreg.Data;
using nscreg.Data.Entities;
using nscreg.Utilities.Models.SampleFrame;

namespace nscreg.Business.SampleFrame
{
    public interface IExpressionParser
    {
        Expression<Func<StatisticalUnit, bool>> Parse(SFExpression sfExpression, NSCRegDbContext context);
    }
}
