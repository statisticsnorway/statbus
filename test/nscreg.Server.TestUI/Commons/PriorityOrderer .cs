using System;
using System.Collections.Generic;
using System.Linq;
using Xunit.Abstractions;
using Xunit.Sdk;

namespace nscreg.Server.TestUI.Commons
{
    public class PriorityOrderer : ITestCaseOrderer
    {
        public IEnumerable<TTestCase> OrderTestCases<TTestCase>(IEnumerable<TTestCase> testCases)
            where TTestCase : ITestCase
        {
            var sortedMethods = new SortedDictionary<int, List<TTestCase>>();

            foreach (var testCase in testCases)
            {
                var priority = 0;

                foreach (
                    var attr in
                    testCase.TestMethod.Method.GetCustomAttributes(typeof(OrderAttribute).AssemblyQualifiedName))
                {
                    priority = attr.GetNamedArgument<int>(nameof(OrderAttribute.Priority));
                }

                GetOrCreate(sortedMethods, priority).Add(testCase);
            }

            foreach (var list in sortedMethods.Keys.Select(priority => sortedMethods[priority]))
            {
                list.Sort(
                    (x, y) =>
                        StringComparer.OrdinalIgnoreCase.Compare(x.TestMethod.Method.Name, y.TestMethod.Method.Name));

                foreach (var testCase in list)
                    yield return testCase;
            }
        }

        private static TValue GetOrCreate<TKey, TValue>(IDictionary<TKey, TValue> dictionary, TKey key)
            where TValue : new()
        {
            TValue result;
            return dictionary.TryGetValue(key, out result)
                ? result
                : dictionary[key] = new TValue();
        }
    }
}
