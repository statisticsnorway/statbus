using System;
using System.Collections.Generic;
using System.ComponentModel;
using System.Linq;
using System.Linq.Expressions;
using System.Reflection;
using nscreg.Data.Entities;
using nscreg.Utilities.Enums.SampleFrame;
using nscreg.Utilities.Models.SampleFrame;

namespace nscreg.Business.SampleFrame
{
    public static class PredicateBuilder
    {
        public static List<(Expression<Func<StatisticalUnit, bool>> predicate, ComparisonEnum? comparison)> GetPredicates(
            List<Tuple<ExpressionItem, ComparisonEnum?>> expressionItems)
        {
            var result = new List<(Expression<Func<StatisticalUnit, bool>> predicate, ComparisonEnum? comparison)>();

            foreach (var tuple in expressionItems)
            {
                result.Add((GetPredicate(tuple.Item1), tuple.Item2));
            }

            return result;
        }

        private static Expression<Func<StatisticalUnit, bool>> GetPredicate(ExpressionItem expressionItem)
        {
            if (expressionItem.Field == FieldEnum.Region)
                return GetRegionPredicate(expressionItem);
            if (expressionItem.Field == FieldEnum.MainActivity)
                return GetActivityPredicate(expressionItem);

            return GetUniversalPredicate(expressionItem);
        }

        private static BinaryExpression GetExpression(ExpressionItem expressionItem, Expression property, Expression value)
        {
            switch (expressionItem.Operation)
            {
                case OperationEnum.Equal:
                    return Expression.Equal(property, value);
                case OperationEnum.LessThan:
                    return Expression.LessThan(property, value);
                case OperationEnum.LessThanOrEqual:
                    return Expression.LessThanOrEqual(property, value);
                case OperationEnum.GreaterThan:
                    return Expression.GreaterThan(property, value);
                case OperationEnum.GreaterThanOrEqual:
                    return Expression.GreaterThanOrEqual(property, value);
                case OperationEnum.NotEqual:
                    return Expression.NotEqual(property, value);
                default:
                    return null;
            }

            return null;
        }

        private static Expression<Func<StatisticalUnit, bool>> GetActivityPredicate(ExpressionItem expressionItem)
        {
            var outerParameter = Expression.Parameter(typeof(StatisticalUnit), "x");
            var property = Expression.Property(outerParameter, "ActivitiesUnits");

            var innerParameter = Expression.Parameter(typeof(ActivityStatisticalUnit), "y");
            var left = Expression.Property(innerParameter, typeof(ActivityStatisticalUnit).GetProperty("Activity"));
            left = Expression.Property(left, typeof(Activity).GetProperty("ActivityRevx"));
            
            var right = GetConstantValue(expressionItem.Value, left);
            Expression innerExpression = Expression.Equal(left, right);

            var call = Expression.Call(typeof(Enumerable), "Any", new[] {typeof(ActivityStatisticalUnit)}, property,
                Expression.Lambda<Func<ActivityStatisticalUnit, bool>>(innerExpression, innerParameter));

            var lambda = Expression.Lambda<Func<StatisticalUnit, bool>>(call, outerParameter);

            return lambda;
        }

        private static Expression<Func<StatisticalUnit, bool>> GetRegionPredicate(ExpressionItem expressionItem)
        {
            var parameter = Expression.Parameter(typeof(StatisticalUnit), "x");
            var property = Expression.Property(parameter, typeof(StatisticalUnit).GetProperty("Address"));
            property = Expression.Property(property, typeof(Address).GetProperty("Region"));
            property = Expression.Property(property, typeof(Region).GetProperty("Code"));
            var constantValue = GetConstantValue(expressionItem.Value, property);

            var method = typeof(string).GetMethod("StartsWith", new[] { typeof(string) });
            var startsWith = Expression.Call(property, method, constantValue);

            var lambda = Expression.Lambda<Func<StatisticalUnit, bool>>(startsWith, parameter);
            return lambda;
        }

        private static Expression<Func<StatisticalUnit, bool>> GetUniversalPredicate(ExpressionItem expressionItem)
        {
            var parameter = Expression.Parameter(typeof(StatisticalUnit), "x");
            var property = Expression.Property(parameter, expressionItem.Field.ToString());
            var constantValue = GetConstantValue(expressionItem.Value, property);
            var lambda = Expression.Lambda<Func<StatisticalUnit, bool>>(GetExpression(expressionItem, property, constantValue), parameter);

            return lambda;
        }

        private static Expression GetConstantValue(object value, MemberExpression property)
        {
            var propertyType = ((PropertyInfo)property.Member).PropertyType;
            var converter = TypeDescriptor.GetConverter(propertyType);
            var propertyValue = converter.ConvertFromString(value.ToString());
            var constant = Expression.Constant(propertyValue);
            var constantValue = Expression.Convert(constant, propertyType);

            return constantValue;
        }
    }
}
