using System;

namespace nscreg.Utilities
{
    public class StatisticalUnitEditException : Exception
    {
        public StatisticalUnitEditException(string message, Exception innerException) : base(message, innerException)
        {
        }
    }
}
