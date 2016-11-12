using System.Linq;
using System.Text;

namespace nscreg.Utilities
{
    public static class StringExtensions
    {
        /// <summary>
        /// Checks if string contains only characters from the code page ISO 8859-1 in the range 33 to 126 (inclusive)
        /// </summary>
        /// <param name="value"></param>
        /// <returns></returns>
        public static bool IsPrintable(this string value)
            => Encoding.GetEncoding("ISO-8859-1").GetBytes(value).All(x => x >= 0x21 && x <= 0x7e);
    }
}
