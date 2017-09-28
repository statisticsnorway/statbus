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

        public static Expression<Func<T, bool>> GetPredicate<T>(decimal? turnoverFrom, decimal? turnoverTo,
            decimal? employeesNumberFrom, decimal? employeesNumberTo, ComparisonEnum? comparison)
        {
            var turnoverFromExpression = turnoverFrom == null
                ? null
                : GetSearchPagePredicate<T>(turnoverFrom, "Turnover", OperationEnum.GreaterThan);
            var turnoverToExpression = turnoverTo == null
                ? null
                : GetSearchPagePredicate<T>(turnoverTo, "Turnover", OperationEnum.LessThan);
            Expression<Func<T, bool>> turnoverExpression = null;

            if (turnoverFromExpression != null && turnoverToExpression != null)
                turnoverExpression = ExpressionParser.GetPredicateOnTwoExpressions(turnoverFromExpression,
                    turnoverToExpression, ComparisonEnum.And);
            else if (turnoverFromExpression != null && turnoverToExpression == null)
                turnoverExpression = turnoverFromExpression;
            else if (turnoverFromExpression == null && turnoverToExpression != null)
            {
                var nullPredicate = GetNullPredicate<T>("Turnover", typeof(decimal?));
                turnoverExpression =
                    ExpressionParser.GetPredicateOnTwoExpressions(nullPredicate, turnoverToExpression,
                        ComparisonEnum.Or);
            }

            var employeesFromExpression = employeesNumberFrom == null
                ? null
                : GetSearchPagePredicate<T>(employeesNumberFrom, "Employees", OperationEnum.GreaterThan);
            var employeesToExpression = employeesNumberTo == null
                ? null
                : GetSearchPagePredicate<T>(employeesNumberTo, "Employees", OperationEnum.LessThan);
            Expression<Func<T, bool>> employeesExpression = null;

            if (employeesFromExpression != null && employeesToExpression != null)
                employeesExpression = ExpressionParser.GetPredicateOnTwoExpressions(employeesFromExpression,
                    employeesToExpression, ComparisonEnum.And);
            else if (employeesFromExpression != null && employeesToExpression == null)
                employeesExpression = employeesFromExpression;
            else if (employeesFromExpression == null && employeesToExpression != null)
            {
                var nullPredicate = GetNullPredicate<T>("Turnover", typeof(decimal?));
                employeesExpression =
                    ExpressionParser.GetPredicateOnTwoExpressions(nullPredicate, employeesToExpression,
                        ComparisonEnum.Or);
            }

            Expression<Func<T, bool>> result = null;

            if (turnoverExpression != null && employeesExpression != null)
                result = ExpressionParser.GetPredicateOnTwoExpressions(turnoverExpression, employeesExpression,
                    comparison ?? ComparisonEnum.Or);
            else if (turnoverExpression != null && employeesExpression == null)
                result = turnoverExpression;
            else if (turnoverExpression == null && employeesExpression != null)
                result = employeesExpression;

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

        private static Expression<Func<T, bool>> GetSearchPagePredicate<T>(decimal? value, string fieldName, OperationEnum operation)
        {
            var parameter = Expression.Parameter(typeof(T), "x");
            var property = Expression.Property(parameter, fieldName);
            var constantValue = GetConstantValue(value, property);

            var expression = operation == OperationEnum.GreaterThan
                ? Expression.GreaterThan(property, constantValue)
                : Expression.LessThan(property, constantValue);
            var lambda = Expression.Lambda<Func<T, bool>>(expression, parameter);

            return lambda;
        }

        private static Expression<Func<T, bool>> GetNullPredicate<T>(string fieldName, Type fieldType)
        {
            var parameter = Expression.Parameter(typeof(T), "x");
            var property = Expression.Property(parameter, fieldName);
            var constantValue = Expression.Constant(null, fieldType);

            var expression = Expression.Equal(property, constantValue);
            var lambda = Expression.Lambda<Func<T, bool>>(expression, parameter);

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
