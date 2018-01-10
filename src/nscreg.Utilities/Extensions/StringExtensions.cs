using System.Linq;
using System.Text;

namespace nscreg.Utilities.Extensions
{
    /// <summary>
    /// String Extensions class
    /// </summary>
    public static class StringExtensions
    {
        /// <summary>
        /// Checks if string contains only characters from the code page ISO 8859-1 in the range 33 to 126 (inclusive)
        /// </summary>
        /// <param name="value"></param>
        /// <returns></returns>
        public static bool IsPrintable(this string value)
            => value.HasValue()
            && Encoding.GetEncoding("ISO-8859-1").GetBytes(value).All(x => x >= 0x21 && x <= 0x7e);

        /// <summary>
        /// Force string to be camel case by lowering first letter's case
        /// </summary>
        /// <param name="value"></param>
        /// <returns></returns>
        public static string LowerFirstLetter(this string value)
            => value.HasValue() ? value.Substring(0, 1).ToLower() + value.Substring(1) : value;

        /// <summary>
        /// Force string to be pascal case by lowering first letter's case
        /// </summary>
        /// <param name="value"></param>
        /// <returns></returns>
        public static string UpperFirstLetter(this string value)
            => value.HasValue() ? value.Substring(0, 1).ToUpper() + value.Substring(1) : value;

        /// <summary>
        /// Check if string is not null and not empty
        /// </summary>
        /// <param name="value"></param>
        /// <returns></returns>
        public static bool HasValue(this string value) => !string.IsNullOrEmpty(value);
    }
}
