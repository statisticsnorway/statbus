using System;
using System.Collections;
using System.ComponentModel;
using System.Linq;
using System.Linq.Expressions;
using System.Reflection;
using nscreg.Data.Entities;
using nscreg.Utilities.Enums.SampleFrame;
using nscreg.Utilities.Models.SampleFrame;
using System.Collections.Generic;
using System.Security.Cryptography.X509Certificates;
using nscreg.Data;

namespace nscreg.Business.SampleFrame
{
    public static class PredicateBuilder
    {
        private static NSCRegDbContext _nscRegDbContext;

        public static Expression<Func<StatisticalUnit, bool>> GetLambda(ExpressionItem expressionItem, NSCRegDbContext context)
        {
            _nscRegDbContext = context;
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
                case OperationEnum.FromTo:
                    return Expression.NotEqual(property, value);
                case OperationEnum.MatchesTemplate:
                    break;
                default:
                    return null;
            }

            return null;
        }

        private static Expression<Func<StatisticalUnit, bool>> GetActivityPredicate(ExpressionItem expressionItem)
        {
            Expression parameter = Expression.Parameter(typeof(StatisticalUnit), "x");
            Expression property = Expression.Property(parameter, "ActivitiesUnits");

            var result =
                Expression.Call(
                    typeof(Enumerable),
                    "FirstOrDefault",
                    new[] { TypeSystem.GetElementType(property.Type) },
                    property);

            var b =_nscRegDbContext.StatisticalUnits.Where(x => x.ActivitiesUnits.FirstOrDefault(y => y.ActivityId == 1) != null);

            var collectionParameter = Expression.Parameter(typeof(IEnumerable<ActivityStatisticalUnit>), "x.ActivitiesUnits");
            var enumNamePredicateParameter = Expression.Parameter(typeof(Func<ActivityStatisticalUnit, bool>), "y");
            var body = Expression.Call(typeof(Enumerable), "SingleOrDefault", new[] { typeof(ActivityStatisticalUnit) },
                collectionParameter, enumNamePredicateParameter);
            var lambda2 =
                Expression
                    .Lambda<Func<IEnumerable<ActivityStatisticalUnit>, Func<ActivityStatisticalUnit, bool>,
                        ActivityStatisticalUnit>>(body, collectionParameter, enumNamePredicateParameter).Compile();

         //   var a = lambda2(_nscRegDbContext.StatisticalUnits.Where(x => lambda2(x.ActivitiesUnits, y => y.ActivityId == 1).ActivityId != 2))



            return null;
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
