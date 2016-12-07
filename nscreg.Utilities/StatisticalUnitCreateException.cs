using System;

namespace nscreg.Utilities
{
    public class StatisticalUnitCreateException : Exception
    {
        public StatisticalUnitCreateException(string message, Exception innerException) : base(message, innerException)
        {
        }
    }
}
