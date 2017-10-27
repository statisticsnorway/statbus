using System;
using System.Linq;
using System.Linq.Expressions;
using System.Reflection;
using nscreg.Data.Entities;
using nscreg.Utilities.Enums.Predicate;

namespace nscreg.Business.PredicateBuilders
{
    /// <inheritdoc />
    /// <summary>
    /// Sample frames predicate builder
    /// </summary>
    public class SampleFramePredicateBuilder : BasePredicateBuilder<StatisticalUnit>
    {
        /// <inheritdoc />
        /// <summary>
        /// Getting sample frame predicate
        /// </summary>
        /// <param name="field">Predicate entity field</param>
        /// <param name="fieldValue">Predicate field value</param>
        /// <param name="operation">Predicate operation</param>
        /// <returns>Predicate</returns>
        public override Expression<Func<StatisticalUnit, bool>> GetPredicate(FieldEnum field, object fieldValue, OperationEnum operation)
        {
            if (field == FieldEnum.Region)
                return GetRegionPredicate(fieldValue);
            if (field == FieldEnum.MainActivity)
                return GetActivityPredicate(fieldValue);

            return base.GetPredicate(field, fieldValue, operation);
        }
        
        private static Expression<Func<StatisticalUnit, bool>> GetActivityPredicate(object fieldValue)
        {
            var outerParameter = Expression.Parameter(typeof(StatisticalUnit), "x");
            var property = Expression.Property(outerParameter, "ActivitiesUnits");

            var innerParameter = Expression.Parameter(typeof(ActivityStatisticalUnit), "y");
            var left = Expression.Property(innerParameter, typeof(ActivityStatisticalUnit).GetProperty("Activity"));
            left = Expression.Property(left, typeof(Activity).GetProperty("ActivityRevx"));

            var right = GetConstantValue(fieldValue, left);
            Expression innerExpression = Expression.Equal(left, right);

            var call = Expression.Call(typeof(Enumerable), "Any", new[] { typeof(ActivityStatisticalUnit) }, property,
                Expression.Lambda<Func<ActivityStatisticalUnit, bool>>(innerExpression, innerParameter));

            var lambda = Expression.Lambda<Func<StatisticalUnit, bool>>(call, outerParameter);

            return lambda;
        }

        private static Expression<Func<StatisticalUnit, bool>> GetRegionPredicate(object fieldValue)
        {
            var parameter = Expression.Parameter(typeof(StatisticalUnit), "x");
            var property = Expression.Property(parameter, typeof(StatisticalUnit).GetProperty("Address"));
            property = Expression.Property(property, typeof(Address).GetProperty("Region"));
            property = Expression.Property(property, typeof(Region).GetProperty("Code"));
            var constantValue = GetConstantValue(fieldValue, property);

            var method = typeof(string).GetMethod("StartsWith", new[] { typeof(string) });
            var startsWith = Expression.Call(property, method, constantValue);

            var lambda = Expression.Lambda<Func<StatisticalUnit, bool>>(startsWith, parameter);
            return lambda;
        }
    }
}
