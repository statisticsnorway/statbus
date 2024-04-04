using NLog;
using nscreg.Data.Entities;
using nscreg.Utilities.Extensions;
using ServiceStack;
using ServiceStack.Text;
using System.Collections.Generic;
using System.Linq;
using System;
using nscreg.Resources.Languages;

namespace nscreg.Business.DataSources
{
    public static class CsvParser
    {
        // Todo: to reflection implementation
        private static readonly string[] StatisticalUnitArrayPropertyNames = new[] { nameof(StatisticalUnit.Activities), nameof(StatisticalUnit.Persons), nameof(StatisticalUnit.ForeignParticipationCountriesUnits) };
        private static readonly KeyValueTupleComparer CsvColumnValueComparer = new KeyValueTupleComparer();

        public static List<Dictionary<string, object>> GetParsedEntities(string rawLines, string delimiter, (string source, string target)[] variableMappingsArray)
        {
            if (rawLines.Length == 0) return new List<Dictionary<string, object>>();

            CsvConfig.ItemSeperatorString = delimiter;
            var lines = rawLines.Split(new char[] { '\r','\n' }).Skip(1).Where(x => !string.IsNullOrEmpty(x));
            List<Dictionary<string, string>> rowsFromCsv;
            try
            {
                rowsFromCsv = rawLines.FromCsv<List<Dictionary<string, string>>>();
            }
            catch(Exception ex)
            {
                throw new Exception(nameof(Resource.FileDataFormatError), ex);
            }
            var rowsFromCsvCount = rowsFromCsv.Count();

            //If the file is problematic and the number of lines after conversion is less than the input parsing does not work
            if (rowsFromCsvCount != lines.Count())
            {
                Exception ex = new Exception(Resource.UploadedFileProblem);
                ex.Data.Add("ProblemLine", $"{lines.ElementAt(rowsFromCsvCount - 1)}\nLine number: {rowsFromCsvCount + 1}");
                throw ex;
            }
            var resultDictionary = new List<Dictionary<string, object>>();
            if (!rowsFromCsv.Any()) return new List<Dictionary<string, object>>();

            // Transform to array of (target, value) according to mapping for the first row
            var unitPartCsv = GetUnitPartCsvAfterMapping(variableMappingsArray, rowsFromCsv[0]);
            // fill units
            for (var j = 0; j < rowsFromCsv.Count;)
            {
                var unitResult = new Dictionary<string, object>();

                unitPartCsv.Where(x => !StatisticalUnitArrayPropertyNames.Contains(x.targetKeySplitted[0]))
                    .ForEach(csvUnitPrimitiveProperty =>
                        unitResult.Add(csvUnitPrimitiveProperty.targetKey, csvUnitPrimitiveProperty.value)
                    );

                unitPartCsv.Where(x => StatisticalUnitArrayPropertyNames.Contains(x.targetKeySplitted[0])).GroupBy(x => x.targetKeySplitted[0])
                    .ForEach(csvUnitArrayProperty =>
                        // If it is an array, we are sure that keySplitted.Length == 3 (Like Activities.Activity.SomeOtherPartWith.Possible.Dots)
                        //So, csvUnitArrayProperty.Key is a value from statisticalUnitArrayPropertyNames variable
                        AppendValuesToArrayProperties(csvUnitArrayProperty, unitResult)
                    );

                // next rows can be a continuation of a unit. If so, they contain the same values for primitive fields and new values for arrays. So we have to collect new values to the arrays
                j++;

                var firstPartOfUnit = unitPartCsv;
                while (j < rowsFromCsv.Count)
                {
                    //// Transform to array of (target, value) according to mapping
                    unitPartCsv = GetUnitPartCsvAfterMapping(variableMappingsArray, rowsFromCsv[j]);
                    // If new unit started, then break the while cycle
                    if (!IsTheSameUnit(firstPartOfUnit, unitPartCsv)) break;

                    // Get columns which values are parts of array items
                    unitPartCsv.Where(x => StatisticalUnitArrayPropertyNames.Contains(x.targetKeySplitted[0])).GroupBy(x=>x.targetKeySplitted[0])
                        .ForEach(csvUnitArrayProperty =>
                            AppendValuesToArrayProperties(csvUnitArrayProperty, unitResult)
                        );

                    j++;
                }
                resultDictionary.Add(unitResult);
            }
            return resultDictionary;

            void AppendValuesToArrayProperties(IGrouping<string, (string targetKey, string value, string[] targetKeySplitted)> csvUnitArrayProperty, Dictionary<string, object> unitResult)
            {
                if (!unitResult.TryGetValue(csvUnitArrayProperty.Key, out object obj))
                {
                    obj = new List<KeyValuePair<string, Dictionary<string, string>>>()
                    {
                    };
                    unitResult.Add(csvUnitArrayProperty.Key, obj);
                }
                var arrayProperty = obj as List<KeyValuePair<string, Dictionary<string, string>>>;
                var arrayItem = new Dictionary<string, string>();
                foreach (var csvArrayItemProperty in csvUnitArrayProperty)
                {
                    arrayItem[csvArrayItemProperty.targetKeySplitted[2]] = csvArrayItemProperty.value;
                }
                arrayProperty.Add(new KeyValuePair<string, Dictionary<string, string>>(csvUnitArrayProperty.First().targetKeySplitted[1], arrayItem));
            }
        }

        private static bool IsTheSameUnit(IEnumerable<(string targetKey, string value, string[] targetKeySplitted)> originalCsvKeyValues, IEnumerable<(string targetKey, string value, string[] targetKeySplitted)> targetCsvKeyValues)
        {
            var columnValuesForPrimitivePropsOriginal = originalCsvKeyValues.Where(x => !StatisticalUnitArrayPropertyNames.Contains(x.targetKeySplitted[0])).ToList();
            var columnValuesForPrimitivePropsTarget = targetCsvKeyValues.Where(x => !StatisticalUnitArrayPropertyNames.Contains(x.targetKeySplitted[0])).ToList();
            var intersectedCount = columnValuesForPrimitivePropsOriginal.Intersect(columnValuesForPrimitivePropsTarget, CsvColumnValueComparer).Count();
            return intersectedCount == columnValuesForPrimitivePropsOriginal.Count() && intersectedCount == columnValuesForPrimitivePropsTarget.Count();
        }

        private static IEnumerable<(string targetKey, string value, string[] targetKeySplitted)> GetUnitPartCsvAfterMapping((string source, string target)[] variableMappingsArray, Dictionary<string, string> rowsFromCsv)
        {
            return rowsFromCsv.Where(z => z.Value.HasValue()).Join(variableMappingsArray, r => r.Key, m => m.source,
                                (r, m) => (targetKey: m.target, value: r.Value, targetKeySplitted: m.target.Split('.', 3)));
        }


        private class KeyValueTupleComparer : IEqualityComparer<(string targetKey, string value, string[] targetKeySplitted)>
        {
            public bool Equals((string targetKey, string value, string[] targetKeySplitted) x, (string targetKey, string value, string[] targetKeySplitted) y)
            {
                return x.targetKey == y.targetKey && x.value == y.value;
            }

            public int GetHashCode((string targetKey, string value, string[] targetKeySplitted) obj)
            {
                return obj.targetKey.GetHashCode() ^ obj.value.GetHashCode();
            }
        }
    }


}
