using System.Collections.Generic;
using System.Linq;

namespace nscreg.Utilities
{
    /// <summary>
    /// Класс сопоставления переменных источника данных
    /// </summary>
    public static class DataSourceVariableMappingHelper
    {
        /// <summary>
        /// Метод преобразования строки в словарь
        /// </summary>
        /// <param name="variablesMapping">Переменная сопоставление</param>
        /// <returns></returns>
        public static IReadOnlyDictionary<string, string> ParseStringToDictionary(string variablesMapping)
            => variablesMapping
                .Split(',')
                .ToDictionary(
                    x => x.Split('-')[0],
                    x => x.Split('-')[1]);
    }
}
