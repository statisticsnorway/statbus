using System;
using System.Linq.Expressions;
using nscreg.Utilities.Enums.Predicate;

namespace nscreg.Business.PredicateBuilders
{
    /// <inheritdoc />
    /// <summary>
    /// Search predicate builder
    /// </summary>
    /// <typeparam name="T"></typeparam>
    public class SearchPredicateBuilder<T> : BasePredicateBuilder<T> where T : class
    {
        /// <summary>
        /// Get search predicate
        /// </summary>
        /// <param name="turnoverFrom">TurnoverFrom value</param>
        /// <param name="turnoverTo">TurnoverTo value</param>
        /// <param name="employeesNumberFrom">EmployeesFrom value</param>
        /// <param name="employeesNumberTo">EmployeesTo value</param>
        /// <param name="comparison">Comparison</param>
        /// <returns>Predicate</returns>
        public Expression<Func<T, bool>> GetPredicate(decimal? turnoverFrom, decimal? turnoverTo,
            decimal? employeesNumberFrom, decimal? employeesNumberTo, ComparisonEnum? comparison)
        {
            var turnoverFromExpression = turnoverFrom == null
                ? null
                : GetPredicate(FieldEnum.Turnover, turnoverFrom, OperationEnum.GreaterThan);
            var turnoverToExpression = turnoverTo == null
                ? null
                : GetPredicate(FieldEnum.Turnover, turnoverTo, OperationEnum.LessThan);
            Expression<Func<T, bool>> turnoverExpression = null;

            if (turnoverFromExpression != null && turnoverToExpression != null)
                turnoverExpression =
                    GetPredicateOnTwoExpressions(turnoverFromExpression, turnoverToExpression, ComparisonEnum.And);
            else if (turnoverFromExpression != null)
                turnoverExpression = turnoverFromExpression;
            else if (turnoverToExpression != null)
            {
                var nullPredicate = GetNullPredicate(FieldEnum.Turnover, typeof(decimal?));
                turnoverExpression =
                    GetPredicateOnTwoExpressions(nullPredicate, turnoverToExpression, ComparisonEnum.Or);
            }

            var employeesFromExpression = employeesNumberFrom == null
                ? null
                : GetPredicate(FieldEnum.Employees, employeesNumberFrom, OperationEnum.GreaterThan);
            var employeesToExpression = employeesNumberTo == null
                ? null
                : GetPredicate(FieldEnum.Employees, employeesNumberTo, OperationEnum.LessThan);
            Expression<Func<T, bool>> employeesExpression = null;

            if (employeesFromExpression != null && employeesToExpression != null)
                employeesExpression =
                    GetPredicateOnTwoExpressions(employeesFromExpression, employeesToExpression, ComparisonEnum.And);
            else if (employeesFromExpression != null)
                employeesExpression = employeesFromExpression;
            else if (employeesToExpression != null)
            {
                var nullPredicate = GetNullPredicate(FieldEnum.Turnover, typeof(decimal?));
                employeesExpression =
                    GetPredicateOnTwoExpressions(nullPredicate, employeesToExpression, ComparisonEnum.Or);
            }

            Expression<Func<T, bool>> result = null;

            if (turnoverExpression != null && employeesExpression != null)
                result = GetPredicateOnTwoExpressions(turnoverExpression, employeesExpression,
                    comparison ?? ComparisonEnum.Or);
            else if (turnoverExpression != null)
                result = turnoverExpression;
            else if (employeesExpression != null)
                result = employeesExpression;

            return result;
        }
    }
}
